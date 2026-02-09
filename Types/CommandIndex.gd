extends Resource
class_name CommandIndex

@export var data:Dictionary[String,CommandData] = {}
@export var startmenu:Dictionary[String,Dictionary] = {}
@export var history:Array[String] = []
@export var uicolor:Color = Color("#2f3179")
@export var maxresults:int = 20
