import re,urllib.request,os
plan = [
 ("16300003-notability-home-screen","home-screen.png",0),
 ("16300085-options-menu","options-menu.png",0),
 ("16300068-customize-your-toolbox","toolbar-customization.png",1),
 ("16300204-writing-with-apple-pencil","apple-pencil-gestures.png",0),
 ("16300179-custom-templates-and-note-background","templates-menu.png",0),
 ("16300180-zoom-view","zoom-view.png",2),
 ("16300226-content-manager-and-bulk-actions","content-manager.png",0),
 ("16300018-pdf-outlines","pdf-outlines.png",0),
 ("16300046-notability-learn","learn-panel.png",0),
 ("16300017-study-timer","study-timer.png",1),
 ("16300005-focus-mode","focus-mode.png",0),
 ("16300052-squeeze-gestures-with-apple-pencil-pro","squeeze-menu.png",0),
 ("16696325-tape","tape-toolbox.png",0),
 ("18321210-ink-smoothing","ink-smoothing.png",0),
 ("16764640-calligraphy-pen","calligraphy-pen.png",0),
 ("17737566-graphs","graph-insert.png",0),
 ("17440617-measurement-tool","measurement-tool.png",0),
 ("16300020-organize-notes-with-folders","folder-edit.png",0),
 ("16300162-viewing-your-notes","library-views.png",0),
 ("16300260-text-and-text-boxes","text-toolbar.png",0),
]
skip=re.compile(r'outline|lib-btn|menuOption|draghandle|Record_Outline|/svg/|toolbar\.png',re.I)
for art,name,idx in plan:
    s=open(f'_md/{art}.md').read()
    imgs=[u for a,u in re.findall(r'!\[([^\]]*)\]\((https://[^)]+)\)', s)
          if not skip.search(u.split('?')[0].split('/')[-1])]
    if len(imgs)<=idx:
        print('MISS',art,len(imgs)); continue
    u=imgs[idx].replace('&amp;','&')
    try:
        req=urllib.request.Request(u,headers={'User-Agent':'Mozilla/5.0'})
        d=urllib.request.urlopen(req,timeout=40).read()
        open(f'images/{name}','wb').write(d)
        print('OK',name,len(d))
    except Exception as e:
        print('ERR',name,e)
