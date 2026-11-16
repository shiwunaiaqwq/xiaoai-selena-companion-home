"""Character-specific rooms shared by the home page, planner and CabinWorld."""
from copy import deepcopy
import json
from pathlib import Path
import re

LAYOUT = json.loads(Path(__file__).with_name('cabin_layout.json').read_text(encoding='utf-8'))
LAYOUT_VERSION = LAYOUT['version']
ROOMS = LAYOUT['rooms']

def rooms_for(character):
    """Return only real, available rooms for this resident, with private room names."""
    result = []
    for original in ROOMS:
        if character not in original.get('characters', LAYOUT['characters']):
            continue
        room = deepcopy(original)
        room['name'] = room.get('names', {}).get(character, room['name'])
        room['description'] = room.get('descriptions', {}).get(character, room['description'])
        room['furniture']=room.get('furniture_by_character',{}).get(character,room.get('furniture',[]))
        if isinstance(room['zone'], dict):
            room['zone'] = room['zone'][character]
        result.append(room)
    return result

def canonical_room(character, room, activity=''):
    """Resolve former room IDs; do not invent a destination for absent map scenes."""
    if not isinstance(room, str):
        return room
    aliases = {**LAYOUT['aliases']['common'], **LAYOUT['aliases'].get(character, {})}
    room = aliases.get(room, room)
    if room == 'kitchen' and re.search(r'吃|用餐|早餐|午餐|晚餐|早饭|午饭|晚饭', activity):
        if not re.search(r'准备|做饭|做菜|烹|煮|泡|冲|洗菜|备餐|备菜|烘|收拾|清洗', activity):
            return 'dining'
    return room

def room_label(character, room):
    """Name a current or historical location without deleting legacy records."""
    for item in rooms_for(character):
        if item['id'] == room:
            return item['name']
    return LAYOUT['legacy_names'].get(room, str(room or '待同步'))

def adapt_plan(character, payload):
    """Bound new actions to actual map locations and this character's own spaces."""
    result = dict(payload)
    result['room'] = canonical_room(character, result.get('room'), result.get('activity', ''))
    if result['room'] not in {r['id'] for r in rooms_for(character)}:
        raise ValueError('Room is not available for this resident in CabinWorld')
    from .activities import bind_plan
    return bind_plan(character,result)

def project_state(character, state):
    """Project legacy current state for display without rewriting its saved history."""
    if not state:
        return state
    result = dict(state)
    result['room'] = canonical_room(character, state.get('room'), state.get('activity', ''))
    result['room_name'] = room_label(character, result['room'])
    result['mapped'] = result['room'] in {r['id'] for r in rooms_for(character)}
    return result

def project_event(character, event):
    """Keep a past event's room ID and text, adding only its readable label."""
    return {**event, 'room_name': room_label(character, event.get('room'))}

def layout_summary(character):
    return {'version': LAYOUT_VERSION, 'name': LAYOUT['name'],
            'floors': [{'id': '1F', 'name': '一楼 · 公共生活区'},
                       {'id': '2F', 'name': '二楼 · 卧室与音乐区'}],
            'selena_study_merged': True,
            'current_character': character}

def room_guidance(character):
    rows = rooms_for(character)
    descriptions = '\n'.join(f"{r['id']}（{r['name']}，{r['floor']}）：{r['description']}" for r in rows)
    return ('\n[小屋世界实际房间]\n两人住在同一栋两层小屋，各自卧室、阳台和音乐区独立。'
            '只有以下地点可用于新的位置与日程，不能编造地图里没有的独立书房、商场或电影院。'
            '赛琳娜书房已合并进二楼右侧卧室，读书、写信与写作使用bedroom，弹琴才去music；'
            '小爱的手柄游戏和看相册在living，练歌与整理歌词在singing。'
            '做饭/泡茶在kitchen，吃饭在dining；外出餐厅用restaurant。'
            '一楼有独立卫生间bathroom，洗漱淋浴泡澡在家中进行；onsen仍是外面的汤屋。'
            '夜间床上看手机仍是bedroom，不意味着起身去了别处。\n' + descriptions + '\n')
