import re,urllib.request
plan=[("16300085-options-menu","options-menu.png"),
("16300068-customize-your-toolbox","toolbar-customization.png"),
("16300204-writing-with-apple-pencil","apple-pencil-gestures.png"),
("16300179-custom-templates-and-note-background","templates-menu.png"),
("16300180-zoom-view","zoom-view.png"),
("16300226-content-manager-and-bulk-actions","content-manager.png"),
("16300018-pdf-outlines","pdf-outlines.png"),
("16300046-notability-learn","learn-panel.png"),
("16300017-study-timer","study-timer.png"),
("16300005-focus-mode","focus-mode.png"),
("16300052-squeeze-gestures-with-apple-pencil-pro","squeeze-menu.png"),
("16696325-tape","tape-toolbox.png"),
("18321210-ink-smoothing","ink-smoothing.png"),
("16764640-calligraphy-pen","calligraphy-pen.png"),
("17737566-graphs","graph-insert.png"),
("17440617-measurement-tool","measurement-tool.png"),
("16300020-organize-notes-with-folders","folder-edit.png"),
("16300162-viewing-your-notes","library-views.png"),
("16300260-text-and-text-boxes","text-toolbar.png"),
("16300122-recording-and-playing-audio","audio-playback.png")]
skip=re.compile(r'outline|lib-btn|menuOption|draghandle|Record_Outline|/svg/|toolbar\.png|ruler\.png|icon',re.I)
for art,name in plan:
    s=open(f'_md/{art}.md').read()
    imgs=[u for a,u in re.findall(r'!\[([^\]]*)\]\((https://[^)]+)\)', s) if not skip.search(u.split('?')[0].split('/')[-1])]
    best=None
    for u in imgs:
        u=u.replace('&amp;','&')
        try:
            req=urllib.request.Request(u,headers={'User-Agent':'Mozilla/5.0'})
            d=urllib.request.urlopen(req,timeout=25).read()
        except Exception as e:
            continue
        if best is None or len(d)>len(best): best=d
    if best and len(best)>40000:
        open(f'images/{name}','wb').write(best); print('OK',name,len(best))
    else:
        print('SKIP',name,len(best) if best else 0)
