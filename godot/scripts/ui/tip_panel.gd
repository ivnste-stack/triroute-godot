class_name TipPanel
extends PanelContainer
## A glass panel whose tooltip is built by a function (rich content: badges, bars) instead of plain text.

var tip_builder: Callable


func _make_custom_tooltip(_for_text: String) -> Object:
	return tip_builder.call() if tip_builder.is_valid() else null
