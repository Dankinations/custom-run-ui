class_name CommandData
extends Resource

@export var short: String

func _init(x:String="") -> void:
	if x != "":
		self.short = x
