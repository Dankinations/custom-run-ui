extends Node2D

signal save_data()
signal done_getting_start(args)
signal finished_loading_icon(curr:int,max:int,what:String)
signal finished_updating_path(CommandIndex)
signal submit(new_text:String)

var pathres:CommandIndex
var dragging
@onready var window = get_window()
@onready var appdata = ProjectSettings.globalize_path("user://")
@onready var db_mode = "DEBUG" in OS.get_cmdline_args()
@onready var item_list = $popup/ItemList
@onready var swindow = $SettingsWindow
var lastContent = ""
var curridx = 0
var shellPrefixCommands = ["shell:desktop","shell:startup","shell:downloads","shell:programs"]
var custom = ["exit","reload"]
var pressedTab = false
var thread:Thread
var submitted = false
var waited_refresh = false

var global_color = Color("2f3179")
const search_possibilities = {
		"google:" : "https://www.google.com/search?q=",
		"duckduckgo:" : "https://www.duckduckgo.com/?q=",
}
const window_offset = Vector2i(0,200)
const window_size = Vector2i(400,200)

func _ready() -> void:
	submit.connect(_on_text_submitted)
	save_data.connect(func():
		ResourceSaver.save(pathres,"user://path_cache.tres"))
	done_getting_start.connect(save_data.emit)
	finished_updating_path.connect(func(n):
		pathres = n
		update_colors(pathres.uicolor)
		swindow.get_node("Main/BGColor").color = pathres.uicolor
		swindow.get_node("Main/Results").value = pathres.maxresults
		)
	finished_loading_icon.connect(func(curr,max,n):
		$loading/Main.text = 'Loading... [%d/%d] %s' % [curr,max,n]
		)
	
	update_path()
	get_tree().set_auto_accept_quit(false)
	set_process_input(true)
	
	var a = DisplayServer.screen_get_size()
	$loading.size = Vector2i(a.x,16)
	window.size = window_size
	window.position = Vector2i(a.x/2-window.size.x/2,0-window.size.y/2-window.size.y)
	tween_main("position",Vector2i(a.x/2-window.size.x/2,0-window.size.y/2),func(): pass)
	
	swindow.position = Vector2i(a.x/2-swindow.size.x/2,a.y/2-swindow.size.y/2)
	swindow.set_meta("desired",Vector2(swindow.position.x,swindow.position.y))
	
	if !DirAccess.dir_exists_absolute(appdata.path_join("icons")):
		DirAccess.make_dir_absolute(appdata.path_join("icons"))
	
	for x in $Main.get_children():
		if x is RichTextLabel:
			x.add_theme_color_override("Default",global_color.lerp(Color(1,1,1),.5))
		if x is Panel:
			x.add_theme_color_override("bg_color",global_color)
			x.add_theme_color_override("border_color",global_color.lerp(Color(0, 0, 0),.5))
		
	$Main/Prompt.gui_input.connect(func(e:InputEvent):
		if e is InputEventKey:
			var arrow = (e.keycode == KEY_UP or e.keycode == KEY_DOWN)
			if arrow: $Main/Prompt.accept_event()
			if e.pressed and (arrow or e.keycode == KEY_ENTER):
				if arrow and item_list.item_count > 0:
					curridx = clamp(curridx + (-1 if e.keycode == KEY_UP else 1),0,max(item_list.item_count-1,0))
					item_list.select(curridx)
					item_list.ensure_current_is_visible()
				if e.keycode == KEY_ENTER and !submitted and (waited_refresh or $popup/ItemList.item_count <= 1):
					$Main/Prompt.accept_event()
					waited_refresh = false
					if Input.is_key_pressed(KEY_CTRL) and Input.is_key_label_pressed(KEY_SHIFT):
						submit.emit($Main/Prompt.text)
						submitted = true
						return
					if !pressedTab and $popup.visible and $popup/ItemList.item_count >= 1:
						pressedTab = true
						$Main/Prompt.text = item_list.get_item_text(curridx)
						curridx = 0
						$Main/Prompt.caret_column = $Main/Prompt.text.length()
						item_list.select(curridx)
						item_list.ensure_current_is_visible()
						update_autocomplete($Main/Prompt.text)
						return
					if pressedTab or item_list.item_count <= 0:
						submit.emit($Main/Prompt.text)
						submitted = true
					
	)
	window.grab_focus()
	await get_tree().process_frame
	$Main/Prompt.grab_focus()
	$popup.position = window.position + window_offset

func update_path():
	var n:CommandIndex
	if ResourceLoader.exists("user://path_cache.tres"):
		n = ResourceLoader.load("user://path_cache.tres")
	else:
		n = ResourceLoader.load("res://CommandIndex.tres")
	
	var path_dirs = OS.get_environment("PATH").split(";")
	var exts = Array(OS.get_environment("PATHEXT").split(";")) if OS.get_environment("PATHEXT") else [".exe",".bat",".com",".cmd",".msc"]
	
	if len(n.startmenu) == 0:
		get_start_programs()
	
	for dir in path_dirs:
		var da = DirAccess.open(dir)
		if da == null: continue
		
		da.list_dir_begin()
		var file = da.get_next()
		while file != "":
			for ext in exts:
				if file.to_lower().ends_with(ext.to_lower()):
					var vname = file.substr(0,file.length()-ext.length())
					n.data[dir + "/" + file] = CommandData.new(vname)
			file = da.get_next()
			
		da.list_dir_end()
	finished_updating_path.emit.call_deferred(n)
	

func fuzzy_score(input, word):
	input = input.to_lower()
	word = word.to_lower()
	var i = 0
	var score = 0
	for c in word:
		if i < input.length() and c == input[i]:
			i += 1
			score += 10
		else:
			score -= 1
	return score if i == input.length() else -999

var popup_tweens:Dictionary[String,Tween] = {"size":null,"position":null}
func tween_popup(typ:String,val:Vector2i,finished:Callable):
	if popup_tweens[typ]: popup_tweens[typ].cancel_free()
	var t = create_tween()
	t.set_ease(Tween.EASE_OUT); t.set_trans(Tween.TRANS_EXPO)
	t.tween_property($popup,typ,
		val,
	.5)
	popup_tweens[typ] = t
	t.finished.connect(finished)

var main_tweens:Dictionary[String,Tween] = {"size":null,"position":null}
func tween_main(typ:String,val:Vector2i,finished:Callable):
	if main_tweens[typ]: main_tweens[typ].cancel_free()
	var t = create_tween()
	t.set_ease(Tween.EASE_OUT); t.set_trans(Tween.TRANS_EXPO)
	t.tween_property(window,typ,
		val,
	.5)
	main_tweens[typ] = t
	t.finished.connect(finished)

func delayed_callback(callback: Callable, delay: float) -> void:
	var timer = get_tree().create_timer(delay)
	timer.connect("_on_timer_timeout",func(): callback.call(); timer.free())

func handle_dir(path:String):
	var lnks = []
	var dir = DirAccess.open(path)
	dir.list_dir_begin()
	var x = dir.get_next()
	while x != "":
		if !dir.current_is_dir():
			if x.to_lower().ends_with(".lnk") and not "uninstall" in x.to_lower():
				lnks.append('"' + path.path_join(x) + '"')
		else:
			lnks += handle_dir(path.path_join(x))
		if db_mode:
			print_rich("[color=MEDIUM_SPRING_GREEN][font_size=15]Handled %s![/font_size][/color][font_size=10][color=LIGHT_SLATE_GRAY][u][url=%s](%s)[/url][/u][/color][/font_size]" % [x,path.path_join(x),path.path_join(x)])
		x = dir.get_next()
	dir.list_dir_end()
	return lnks

func get_start_programs():
	$loading.visible = true
	var py_path = ProjectSettings.globalize_path("res://ico_to_png.py") if OS.is_debug_build() else OS.get_executable_path().get_base_dir().path_join("ico_to_png.py")
	DirAccess.remove_absolute("user://icons")
	DirAccess.make_dir_absolute("user://icons")
	if db_mode:
		print_rich("[b][font_size=40]Getting start programs...[/font_size][/b]")
	var programs_path = OS.get_environment("APPDATA").replace("\\","/").path_join("Microsoft/Windows/Start Menu/Programs")
	var global_programs_path = OS.get_environment("PROGRAMDATA").replace("\\","/").path_join("Microsoft/Windows/Start Menu/Programs")
	var lnks = []
	pathres.startmenu = {}
	
	if DirAccess.dir_exists_absolute(programs_path):
		lnks = handle_dir(programs_path) + handle_dir(global_programs_path) if DirAccess.dir_exists_absolute(global_programs_path) else []
	else:
		return []
	
	py_path = '"' + py_path + '"'
	@warning_ignore("shadowed_global_identifier")
	var max = len(lnks)
	var curr = [0]
	var do = func():
		for x in lnks:
			curr[0] += 1
			finished_loading_icon.emit.call_deferred(curr[0],max,x)
			var temp = (x.split("/")[-1]).replace('"',"")
			var save_icon_path = appdata+"icons/".path_join(temp + '.png')
			var to_add = 'py ' + py_path + ' ' + x + ' "' + save_icon_path.replace('"',"")
			pathres.startmenu[x] = {"icon":save_icon_path,"short":(x.split("/")[-1]).replace('"',"").replace(".lnk","")}
			OS.call('create_process',"cmd.exe", ["/c", to_add])
		done_getting_start.emit.call_deferred()
	thread = Thread.new()
	thread.start(do)

func update_autocomplete(v:String):
	var list = item_list
	list.clear()
	
	var scores = {}
	var icons = {
		"duckduckgo:": "res://Search Engines/duckduckgo.png",
		"google:": "res://Search Engines/google.png"
	}
	
	for x in search_possibilities.keys():
		var score = fuzzy_score(v,x)
		if score > -999:
			scores[x] = score
	
	for x in pathres.data.keys():
		var score = fuzzy_score(v,pathres.data[x].short)
		if score > -999:
			scores[x] = score
	
	for x in pathres.startmenu.keys():
		var data = pathres.startmenu[x]
		var add:String = "App: " + data.short
		var score = fuzzy_score(v,add)
		if score > -999:
			scores[add] = score
			icons[add] = data.icon
		
	for x in shellPrefixCommands:
		var score = fuzzy_score(v,x)
		if score > -999:
			scores[x] = score
	
	for x in custom:
		var score = fuzzy_score(v,x)
		if score > -999:
			scores[x] = score
	
	## FILE HANDLING ##
	
	var split = v.split("/"); 
	for i in range(len(split)):
		if !split[i]: continue
		if split[i] == "": split.remove_at(i)
		
	var final = ""
	for i in range(len(split)):
		final += split[i]
		if i < len(split)-1:
			final += "/"
	
	var find = final.rfind("/")
	var last = final.substr(0,find) if find != -1 else ""
	
	if len(last) != 0:
		if DirAccess.dir_exists_absolute(last):
			var has = ("/" if !last.ends_with("/") else "")
			var dir = DirAccess.open(last+has); if not dir: return
			dir.list_dir_begin()
			var x = dir.get_next()
			while x != "" and !(".gd" in x):
				var compare = last + has + x + ("/" if dir.current_is_dir() else "")
				var score = fuzzy_score(v,compare)
				if score > -999:
					scores[compare] = score
				x = dir.get_next()
			dir.list_dir_end()
	
	var items = []
	for x:String in scores:
		items.append(
		{
			"value":scores[x],
			"key":x,
			"exception": x.to_lower() in search_possibilities.keys() or x.begins_with("App: ") or x.begins_with("shell:") or x.contains(":/") or x in custom,
			"icon" : icons[x] if x in icons else null
		})
	
	items.sort_custom(func(a,b):
		return a["value"] > b["value"]
		)
	
	var longest = 0
	var total_height = 0
	var font = item_list.get_theme_font("font")
	var font_size = item_list.get_theme_font_size("font_size")
	var font_height = font.get_height(font_size)
	var style:StyleBoxEmpty = item_list.get_theme_stylebox("panel")
	var padding_vertical = style.get_margin(SIDE_TOP) + style.get_margin(SIDE_BOTTOM)
	
	var vsep = item_list.get_theme_constant("v_separation")
	var icon_height = item_list.fixed_icon_size.y
	
	for x in items:
		if not x.exception:
			if len(pathres.data[x.key].short) > longest:
				longest = len(x.key)
			total_height += font_height+vsep if item_list.item_count < pathres.maxresults else 0
			list.add_item(pathres.data[x.key].short)
		else:
			if len(x.key) > longest:
				longest = len(x.key)
			if x.key in icons:
				if !FileAccess.file_exists(icons[x.key]):
					list.add_item(x.key)
					total_height += (font_height + vsep) if item_list.item_count < pathres.maxresults else 0
				else:
					var img = Image.load_from_file(icons[x.key])
					var t = ImageTexture.create_from_image(img)
					list.add_item(x.key,t)
					total_height += (icon_height + vsep) if item_list.item_count < pathres.maxresults else 0
					if len(x.key)+10 > longest:
						longest = len(x.key)+10
			else:
				total_height += (font_height + vsep) if item_list.item_count < pathres.maxresults else 0
				list.add_item(x.key)

	tween_popup("size",Vector2i(longest*10,total_height+padding_vertical),func():
		item_list.ensure_current_is_visible()
	)
	curridx = clamp(curridx,0,item_list.item_count-1)
	if curridx > -1:
		item_list.select(curridx)
	
	if $popup.visible:
		@warning_ignore("integer_division")
		tween_popup("position",window.position + window_offset - Vector2i(longest*10/2-window.size.x/2,0),func():
			item_list.ensure_current_is_visible()
			)

func play_out_anim():
	tween_popup("size",Vector2i(0,0),func(): pass)
	tween_popup("position",$popup.position+Vector2i($popup.size.x/2,0),func(): pass)
	tween_main("position",window.position-Vector2i(0,100),func(): pass)

func _on_text_submitted(new_text: String) -> void:
	if submitted: return
	submitted = true
	for engine in search_possibilities.keys():
		if engine in new_text.to_lower():
			var g = new_text.to_lower().substr(0,len(engine))
			OS.shell_open(
				search_possibilities[g] + new_text.substr(len(g))
				)
			exit_safely()
			return
		
	if new_text.to_lower() == "exit":
		exit_safely()
		return
		
	if new_text.to_lower() == "reload":
		play_out_anim()
		await get_tree().create_timer(1).timeout
		get_start_programs()
		exit_safely()
		return
	
	if new_text.begins_with("App: "):
		var without = new_text.replace("App: ","")
		for i in pathres.startmenu:
			var v = pathres.startmenu[i]
			if v.short == without:
				OS.shell_open(i)
				exit_safely()
	
	if ":/"  in new_text:
		OS.shell_open(new_text)
		exit_safely()
		return
	
	if new_text.begins_with("cmd") or new_text == "cmd":
		var home = OS.get_environment("USERPROFILE")
		var params = new_text.substr(3)
		var extra = ' "' if !params else " && " + params + ' "'
		OS.create_process("cmd.exe", ["/k", ' start cmd /k "cd /d ' + home + extra])
		exit_safely()
		return
	
	if new_text.to_lower() == "refreshenv":
		update_path()
		OS.create_process("cmd.exe",["/c",new_text])
		exit_safely()
		return
	
	if new_text.to_lower() in shellPrefixCommands:
		var p = new_text.substr(6)
		var path
		if p == "startup":
			path = OS.get_environment("APPDATA") + "\\Microsoft\\Windows\\Start Menu\\Programs\\Startup"
		elif p=="desktop":
			path = OS.get_environment("USERPROFILE") + "\\Desktop"
		else:
			path = OS.get_environment("USERPROFILE") + "\\Downloads"
		OS.shell_open(path)
		exit_safely()
		return
	
	OS.create_process("cmd.exe",["/c" + " " + new_text])
	exit_safely()

func _on_timer_timeout() -> void:
	waited_refresh = true
	if $Main/Prompt.text.strip_edges() != "":
		if $Main/Prompt.text.strip_edges() == lastContent: return
		lastContent = $Main/Prompt.text.strip_edges()
		if pressedTab:
			pressedTab = false
			return
		$popup.visible = true
		update_autocomplete(lastContent)
	else:
		$popup.visible = false

func _on_item_list_item_clicked(index: int, _at_position: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index != 1: return
	if curridx == index:
		if pressedTab:
			submit.emit(item_list.get_item_text(curridx))
		pressedTab = true
		$Main/Prompt.text = item_list.get_item_text(curridx)
		curridx = 0
		$Main/Prompt.caret_column = $Main/Prompt.text.length()
	
	curridx = index
	item_list.select(curridx)
	item_list.ensure_current_is_visible()
	update_autocomplete($Main/Prompt.text)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		exit_safely()

func exit_safely(playanim=true):
	var done = func():
		ResourceSaver.save(pathres,"user://path_cache.tres")
		if playanim:
			play_out_anim()
			await get_tree().create_timer(.5).timeout
		get_tree().quit()
	if thread:
		if thread.is_started(): done_getting_start.connect(done)
	else:
		done.call()

func _on_settings_toggled(toggled_on: bool) -> void:
	swindow.visible = toggled_on

func _on_top_bar_gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.button_index == 1:
			swindow.set_meta("dragging",e.pressed)
			if e.pressed:
				var initial = Vector2(swindow.position.x,swindow.position.y)
				var mp = DisplayServer.mouse_get_position(); mp = Vector2(mp.x,mp.y)
				var diff = mp-initial
				swindow.set_meta("grabOffset",Vector2(diff.x,diff.y))

func _on_settings_window_focus_exited() -> void:
	swindow.set_meta("dragging",false)

func _process(delta: float) -> void:
	if swindow.visible:
		var normal = 1.0/60.0
		var speed = delta/normal
		var initial = Vector2(swindow.position.x,swindow.position.y)
		if swindow.get_meta("dragging"):
			var mp = DisplayServer.mouse_get_position(); mp = Vector2(mp.x,mp.y)
			swindow.set_meta("desired",mp-swindow.get_meta("grabOffset"))
		
		var d = swindow.get_meta("desired")
		var next = initial.lerp(d,.25*speed)
		swindow.position = Vector2i(next.x,next.y)

func update_colors(color):
	var panel = swindow.get_node("Main")
	panel.self_modulate = color
	panel = swindow.get_node("TopBar")
	panel.self_modulate = color
	panel = $Main/Panel
	panel.self_modulate = color
	panel = $popup/Panel
	panel.self_modulate = color
	pathres.uicolor = color

func _on_bg_color_color_changed(color: Color) -> void:
	update_colors(color)

func _on_exit_settings_tab_pressed() -> void:
	swindow.visible = false
	$Main/Settings.button_pressed = false

func _on_results_value_changed(value: float) -> void:
	pathres.maxresults = round(value)
