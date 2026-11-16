"""Shared meal rhythm and fair per-meal chores, driven by the original home clock."""
from datetime import datetime,timedelta,timezone
from .activities import BY_ID
from .layout import LAYOUT

CN=timezone(timedelta(hours=8))
PEOPLE=('xiaoai','selena');NAMES={'xiaoai':'小爱','selena':'赛琳娜'}
MEALS=(('breakfast','早餐',8*60,25),('lunch','午饭',12*60,30),('dinner','晚饭',18*60,30))
WAKE_MINUTES=LAYOUT.get('daily_rhythm',{}).get('wake_minutes',{'selena':420,'xiaoai':460})

def is_sleep_time(character,at):return at.hour*60+at.minute<WAKE_MINUTES[character]
def wake_at(character):return f'{WAKE_MINUTES[character]//60:02}:{WAKE_MINUTES[character]%60:02}'

def assignments(day,index):
    cook='selena' if index==0 else PEOPLE[(day.toordinal()+index-1)%2]
    return cook,PEOPLE[1-PEOPLE.index(cook)]

def schedule(at=None):
    at=at or datetime.now(CN);rows=[]
    for i,(id,name,start,duration) in enumerate(MEALS):
        cook,washer=assignments(at.date(),i)
        rows.append({'id':id,'name':name,'eat_at':f'{start//60:02}:{start%60:02}',
          'cook_at':f'{(start-30)//60:02}:{(start-30)%60:02}',
          'wash_at':f'{(start+duration)//60:02}:{(start+duration)%60:02}',
          'cook':NAMES[cook],'wash_dishes':NAMES[washer]})
    return {'date':at.date().isoformat(),'meals':rows,'wake_at':{who:wake_at(who) for who in PEOPLE},
      'care':[{'time':'07:00','name':'赛琳娜起床洗漱，换衣整理后泡茶'},
              {'time':'07:40','name':'小爱慢慢醒来，看一会儿手机，再洗漱换衣'},
              {'time':'21:30 / 22:00','name':'赛琳娜、小爱先后洗澡或泡澡，随后换好睡衣'},
              {'time':'23:15 / 23:30','name':'赛琳娜、小爱先后睡前洗漱，再回各自卧室'}],
      'rule':'早起的赛琳娜准备早餐，小爱饭后洗碗；午晚餐交换主厨与洗碗，次日继续轮换；主人的共同活动优先'}

def care_current(character,at):
    m=at.hour*60+at.minute;relax='read_bedroom' if character=='selena' else 'sofa_music'
    baths='soak' if (at.date().toordinal()+(0 if character=='selena' else 1))%2 else 'shower'
    phases=(
      [(420,430,'wash'),(430,435,'wardrobe'),(435,440,'mirror'),(440,450,'brew_tea'),
       (1290,1305,baths),(1305,1315,'wardrobe'),(1395,1405,'wash'),(1405,1410,'mirror'),
       (1410,1430,'write_diary'),(1430,1440,'bed_phone')]
      if character=='selena' else
      [(460,465,'bed_phone'),(465,473,'wash'),(473,477,'wardrobe'),(477,480,'mirror'),
       (1320,1335,baths),(1335,1345,'wardrobe'),(1410,1420,'wash'),(1420,1425,'mirror'),(1425,1440,'bed_phone')])
    for start,end,id in phases:
        if start<=m<end:
            card=BY_ID[id]
            until=(at.replace(hour=0,minute=0,second=0,microsecond=0)+timedelta(minutes=end)).isoformat(timespec='seconds')
            return {'room':card['room'],'interaction_id':id,'activity':card['title'],'detail':card['detail'],
              'routine_key':f'{at.date().isoformat()}:care:{character}:{start}',
              'routine_until':until,'meal':'日常起居','phase':'care'}
    return None

def current(character,at=None):
    at=at or datetime.now(CN);minute=at.hour*60+at.minute
    care=care_current(character,at)
    if care:return care
    for index,(id,name,start,duration) in enumerate(MEALS):
        if not start-30<=minute<start+duration+15:continue
        cook,washer=assignments(at.date(),index)
        if minute<start:
            phase='cook';until=start
            interaction='cook' if character==cook else 'wash_food'
            detail=('在灶台前照看这一餐的火候' if character==cook else '在水槽旁洗菜，帮忙把食材准备好')
        elif minute<start+duration:
            phase='eat';until=start+duration;interaction=id
            detail='到一楼餐桌前坐好，慢慢吃'+name
        else:
            phase='wash';until=start+duration+15
            interaction='wash_dishes' if character==washer else 'sofa_rest'
            detail='在厨房水槽清洗这一餐的餐具' if character==washer else '饭后在客厅歇一会儿，晚些再接着做自己的事'
        card=BY_ID[interaction]
        end=at.replace(hour=until//60,minute=until%60,second=0,microsecond=0)
        return {'room':card['room'],'interaction_id':interaction,'activity':card['title'],'detail':detail,
          'routine_key':f'{at.date().isoformat()}:{id}:{phase}','routine_until':end.isoformat(timespec='seconds'),
          'meal':name,'phase':phase,'cook':cook,'washer':washer}
    return None

def may_follow(state,at=None):
    at=at or datetime.now(CN)
    # An explicit recent owner instruction is not immediately displaced by a meal tick.
    if state.get('source')=='chat':
        try:
            if (at-datetime.fromisoformat(state['since'])).total_seconds()<3600:return False
        except (KeyError,ValueError):pass
    return True

def needs_update(character,state,at=None):
    at=at or datetime.now(CN)
    if not may_follow(state,at):return False
    plan=current(character,at)
    if plan:return state.get('routine_key')!=plan['routine_key']
    if state.get('routine_key') and state.get('routine_until'):
        try:return at>=datetime.fromisoformat(state['routine_until'])
        except ValueError:return True
    return False
