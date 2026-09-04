class_name Messenger
extends RefCounted
## Гонець: єдиний вихід на клієнтів.
##
## Навіщо окремий клас. Досі кожен виклик `rpc_id` стояв просто в
## `world.gd`, і через це бій не можна було перевірити пробою: `_attack`
## не викликати окремо від мережевого вузла (DECISIONS.md, «Зроблено
## одразу після ревізії»). Тепер бій, черга та поведінка монстрів знають
## лише про гінця; проба підставляє свого, який нічого не шле, а
## записує — і числа бою перевіряються без мережі й без сервера.
##
## Шлях вузла має збігатися на клієнті й сервері, тому самі `@rpc`
## лишаються в `world.gd`; гонець тільки вибирає, КОМУ слати.

## Вузол, від імені якого йде виклик. Його шлях і має збігатися.
var _node: Node
## Звідки береться, хто кого бачить. На клієнті не потрібне — там null.
var _vision: Vision


func _init(node: Node = null, vision: Vision = null) -> void:
	_node = node
	_vision = vision


## Одному з'єднанню. Монстри живуть у від'ємних номерах і з'єднаннями не
## є — їм слати нікуди, і це не помилка, а звичайний випадок.
func to_one(peer: int, method: StringName, args: Array = []) -> void:
	if peer <= 0 or _node == null:
		return
	_node.callv("rpc_id", [peer, method] + args)


## Усім, хто зараз бачить цю істоту (П-43). Хто не бачить — не дізнається
## ні про шкоду, ні про смерть.
func to_watchers(subject: int, method: StringName, args: Array = []) -> void:
	if _vision == null:
		return
	for peer in _vision.watchers_of(subject):
		to_one(peer, method, args)


## Кожному, хто в грі — незалежно від того, хто що бачить.
##
## Це виняток із П-43, і він навмисний: є речі, які стосуються всього
## світу, а не однієї істоти. Перша така — стан святині (П-153):
## зачистили її на іншому кінці мапи, і про це має знати кожен, бо
## далі туди йти всім. Для істот лишається `to_watchers` — щоб не
## розсилати позиції тим, хто нічого не бачить.
func to_all(method: StringName, args: Array = []) -> void:
	if _node == null:
		return
	for peer in _node.multiplayer.get_peers():
		to_one(peer, method, args)


## З клієнта на сервер. Сервер — завжди номер 1.
func to_server(method: StringName, args: Array = []) -> void:
	if _node != null:
		_node.callv("rpc_id", [1, method] + args)


## Повідомлення в чат одному гравцеві.
func notice(id: int, text: String) -> void:
	to_one(id, &"client_notice", [text])
