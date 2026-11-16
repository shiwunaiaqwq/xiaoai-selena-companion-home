"""Furniture-bound action cards; no independent clock or model requests."""
from copy import deepcopy
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import re

CN=timezone(timedelta(hours=8))
CATALOG=json.loads(Path(__file__).with_name('activity_catalog.json').read_text(encoding='utf-8'))
ACTIVITY_VERSION=CATALOG['version']
BY_ID={a['id']:a for a in CATALOG['activities']}

def cards_for(character):
    return [deepcopy(a) for a in CATALOG['activities'] if character in a['characters']]

def period(at):
    h=at.hour
    if h<7:return 'night'
    if h<11:return 'morning'
    if h<14:return 'noon'
    if h<18:return 'afternoon'
    if h<22:return 'evening'
    return 'late'

def allowed_at(card,at):
    p=period(at)
    if at.hour<9 and card['id'] in ('sing_practice','piano'):return False
    if at.hour>=23 and card['id'] in ('sing_practice','piano','arcade_play','park_walk','shop_browse','game_round'):return False
    return p in card['periods'] or ('day' in card['periods'] and p!='night')

def bind_plan(character,payload):
    """Resolve explicit IDs, or conservatively recognize legacy activity titles."""
    result=dict(payload);identifier=result.get('interaction_id') or ''
    if identifier:
        card=BY_ID.get(identifier)
        if not card or character not in card['characters'] or card['room']!=result['room']:
            raise ValueError('Action does not match this resident and room')
        return result
    title=result.get('activity','')
    patterns={
        'bedroom': [('bed_phone',r'手机|回消息|醒来聊'),('sleep',r'睡觉|入睡|安睡'),('wardrobe',r'衣柜|换衣|挑衣'),('mirror',r'照镜|梳妆'),('write_diary',r'写日记|写手记'),('write_letter',r'写信|写作|创作'),('read_letters',r'旧信|翻信|读信'),('read_bedroom',r'阅读|看书')],
        'bathroom':[('shower',r'淋浴|洗澡|冲澡'),('soak',r'泡澡|浴缸'),('wash',r'洗漱|刷牙|洗脸')],
        'kitchen':[('wash_dishes',r'洗碗|洗盘|清洗餐具|刷碗'),('wash_food',r'洗菜|择菜|清洗食材'),('brew_tea',r'泡茶|冲茶'),('prepare_meal',r'准备|食材|备餐'),('cook',r'做饭|做菜|煮|炒|煎|烘')],
        'dining':[('breakfast',r'早餐|早饭'),('lunch',r'午餐|午饭'),('dinner',r'晚餐|晚饭')],
        'living':[('living_tidy',r'收拾|打扫|清扫|整理客厅'),('choose_book',r'选书|挑书|书柜'),('game_round',r'游戏|手柄'),('album',r'相册|回忆'),('drink_tea',r'喝茶|品茶'),('sofa_read',r'阅读|看书'),('sofa_music',r'听.*音乐|听歌'),('sofa_rest',r'休息|歇|喝茶|品茶')],
        'singing':[('listen_take',r'回放|录音'),('lyrics',r'歌词|谱'),('sing_practice',r'唱|练歌')],
        'music':[('music_review',r'回放|录音'),('violin_cabinet',r'展柜|小提琴'),('score',r'乐谱|谱页|改谱|作曲'),('piano',r'弹琴|钢琴|试奏|弹奏')],
        'balcony':[('balcony_plants',r'盆栽|植物|浇水'),('balcony_view',r'风景|天色|吹风|歇')],
        'park':[('park_rest',r'长椅|歇'),('park_walk',r'散步|走')],
        'store':[('shop_browse',r'.')], 'arcade':[('arcade_play',r'.')],
        'restaurant':[('restaurant_meal',r'吃|用餐')], 'onsen':[('onsen_rest',r'休息|歇')],
    }
    valid={a['id'] for a in cards_for(character)}
    for id,pattern in patterns.get(result.get('room'),[]):
        if id in valid and re.search(pattern,title):identifier=id;break
    result['interaction_id']=identifier
    return result

def fallback_scene(character,at=None):
    at=at or datetime.now(CN);h=at.hour
    from .meals import current
    meal=current(character,at)
    ids=['sleep']*7+['wash','sofa_rest','album' if character=='xiaoai' else 'read_bedroom',
         'sing_practice' if character=='xiaoai' else 'piano','sofa_rest','sofa_rest','sofa_rest',
         'lyrics' if character=='xiaoai' else 'write_letter',
         'sing_practice' if character=='xiaoai' else 'piano','balcony_view','balcony_view','sofa_rest',
         'game_round' if character=='xiaoai' else 'music_review','sofa_music','sofa_read',
         'album' if character=='xiaoai' else 'write_diary','bed_phone']
    card=BY_ID[meal['interaction_id'] if meal else ids[h]]
    return {'room':card['room'],'interaction_id':card['id'],'activity':card['title'],
            'detail':card['detail'],'plans':[BY_ID[id]['title'] for id in card['next'][:2]]}

def planner_context(character,state,recent,at=None):
    at=at or datetime.now(CN)
    routine_only={'wash','wardrobe','mirror','shower','soak','breakfast','lunch','dinner','prepare_meal','cook','wash_food','wash_dishes','sleep'}
    available=[a for a in cards_for(character) if allowed_at(a,at) and a['id'] not in routine_only]
    current=BY_ID.get(state.get('interaction_id',''),{})
    next_ids=current.get('next_by_character',{}).get(character,current.get('next',[]))
    recent_ids=[e.get('interaction_id') for e in recent[:4]]
    candidates=[a for a in available if allowed_at(a,at)]
    def score(a):return (3 if a['id'] in next_ids else 0)-(2 if a['id'] in recent_ids else 0)
    candidates.sort(key=score,reverse=True)
    return {'version':ACTIVITY_VERSION,'period':period(at),
      'suggested_next':[a['id'] for a in candidates[:7]],
      'cards':[{**{k:a[k] for k in ('id','room','title','visual')},'next':a.get('next_by_character',{}).get(character,a['next'])} for a in available],
      'guidance':'从适合当下的行动卡选择interaction_id，activity与detail按人设自然写。next是可选衔接，不是强制打卡；继续当前事情时说明真实进展，完成的事情不倒退。洗漱、换衣、泡茶是短暂过渡，不反复耗一整天；三餐优先，做饭洗碗按餐次轮换。练歌或弹琴后可听回放、休息，不永远反复攻克同一段。客厅按行动选择沙发、书柜或整理位置，不能统一成游戏或喝茶。未实现的抽屉开合、照片替换不能声称已经在游戏操作。'}

def activity_guidance():
    return ('\n[家具行动]\n为新的自主日程选择匹配角色和房间的interaction_id，具体文字自由贴合人设。'
            '不进入对方卧室，不占用对方的床、衣柜或专属音乐区。'
            '写信、手记与日记用赛琳娜卧室书桌，钢琴与乐谱在音乐工作室。'
            '屋内洗漱、淋浴和泡澡在一楼卫生间；汤屋是外出地点。'
            '客厅按实际行动分配：游戏、喝茶、阅读、听音乐使用各自动作；选书与收拾客厅要起身，不再统一坐沙发。\n')
