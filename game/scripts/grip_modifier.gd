class_name GripModifier
extends SkeletonModifier3D
## Хват зброї й щита поверх анімації (20.11.2026, слово замовника: «меч, сокира, кинджал, спис,
## посох не тримаються в руках а висять трохи за рукою; щит повинен висіти за рукою а рука із
## щитом бути зігнутою в лікті таким чином щоб щит захищав ліву частину грудної клітини»).
##
## • Пальці руки, що тримає річ, стискаються в кулак (поворот кожної фаланги до долоні, вісь —
##   з пози спокою моделі, тож однаково для будь-якої моделі на скелеті UE).
## • Рука зі щитом: плече опущене трохи вперед, передпліччя — перед грудьми до середини; щит —
##   на передпліччі, лицем уперед, ставиться тут щокадру (у просторі скелета).
## Напрями «вперед/вгору/вправо» — з пози спокою: від п'яти до пальців ноги, від таза до голови.

const FINGERS := ["index", "middle", "ring", "pinky"]
## Кути згину фаланг, градуси: основна, середня, кінцева; великий палець — легше.
const CURL := [70.0, 85.0, 55.0]
const THUMB_CURL := [15.0, 30.0, 30.0]
## Рука зі щитом: напрями плеча й передпліччя (частки вперед, вгору, у бік).
const SHIELD_UPPER := Vector3(0.45, -0.8, 0.2)    # вперед, вгору, назовні (вліво)
const SHIELD_FORE := Vector3(0.2, 0.1, 0.85)      # вперед, вгору, всередину (вправо)
## Щит — на цій частці передпліччя від ліктя, винесений уперед на частку довжини передпліччя.
const SHIELD_AT := 0.55
const SHIELD_OUT := 0.45
## …і зсунутий ліворуч (щит закриває ліву частину грудей, не обличчя).
const SHIELD_LEFT := 0.35

var _curl: Array = []          # [кістка, вісь у кістці, кут у радіанах]
var _shield: Node3D = null
var _shield_scale := 1.0
var _up_i := -1
var _lo_i := -1
var _hand_i := -1
var _fwd := Vector3.FORWARD
var _up := Vector3.UP
var _right := Vector3.RIGHT


## `hands` — кістки кистей, що тримають річ (`hand_r`, `hand_l`); `shield` — вузол щита,
## дитина скелета (або null); `shield_scale` — масштаб речі (метри гри → одиниці скелета).
func setup(skel: Skeleton3D, hands: Array, shield: Node3D, shield_scale: float) -> void:
	_curl.clear()
	_frame(skel)
	for hand: String in hands:
		_curl_hand(skel, hand)
	_shield = shield
	_shield_scale = shield_scale
	_up_i = skel.find_bone("upperarm_l") if shield != null else -1
	_lo_i = skel.find_bone("lowerarm_l") if shield != null else -1
	_hand_i = skel.find_bone("hand_l") if shield != null else -1
	if _up_i == -1 or _lo_i == -1 or _hand_i == -1:
		_up_i = -1


func _frame(skel: Skeleton3D) -> void:
	var foot := skel.find_bone("foot_r")
	var ball := skel.find_bone("ball_r")
	var pelvis := skel.find_bone("pelvis")
	var head := skel.find_bone("head")
	if pelvis != -1 and head != -1:
		_up = (skel.get_bone_global_rest(head).origin
				- skel.get_bone_global_rest(pelvis).origin).normalized()
	if foot != -1 and ball != -1:
		var f := skel.get_bone_global_rest(ball).origin - skel.get_bone_global_rest(foot).origin
		_fwd = (f - _up * f.dot(_up)).normalized()
	_right = _fwd.cross(_up).normalized()


## Долоня (у просторі скелета, поза спокою): нормаль — у бік, куди згинаються пальці; знак —
## за великим пальцем, що лежить з боку долоні.
static func palm(skel: Skeleton3D, hand: String) -> Dictionary:
	var side := "_l" if hand.ends_with("_l") else "_r"
	var h := skel.find_bone(hand)
	var ids := {}
	for n: String in ["index_01", "middle_01", "pinky_01", "thumb_01", "thumb_02"]:
		ids[n] = skel.find_bone(n + side)
		if ids[n] == -1:
			return {}
	var o := skel.get_bone_global_rest(h).origin
	var mid: Vector3 = skel.get_bone_global_rest(ids["middle_01"]).origin - o
	var across: Vector3 = skel.get_bone_global_rest(ids["index_01"]).origin \
			- skel.get_bone_global_rest(ids["pinky_01"]).origin
	var f := mid.normalized()
	var n := across.cross(f).normalized()
	var thumb: Vector3 = skel.get_bone_global_rest(ids["thumb_02"]).origin - o
	if n.dot(thumb - f * thumb.dot(f)) < 0.0:
		n = -n
	return {"finger": f, "normal": n, "across": across.normalized(), "knuckle": mid}


func _curl_hand(skel: Skeleton3D, hand: String) -> void:
	var p := palm(skel, hand)
	if p.is_empty():
		return
	var side := "_l" if hand.ends_with("_l") else "_r"
	var n: Vector3 = p["normal"]
	for finger: String in FINGERS + ["thumb"]:
		var kuty: Array = THUMB_CURL if finger == "thumb" else CURL
		for k in 3:
			var b := skel.find_bone("%s_0%d%s" % [finger, k + 1, side])
			if b == -1:
				continue
			var rest := skel.get_bone_global_rest(b)
			var nxt := skel.find_bone("%s_0%d%s" % [finger, k + 2, side])
			var dir: Vector3 = (skel.get_bone_global_rest(nxt).origin - rest.origin) \
					if nxt != -1 else rest.basis.y
			var axis := dir.normalized().cross(n).normalized()
			if axis.length() < 0.5:
				continue
			_curl.append([b, (rest.basis.inverse() * axis).normalized(),
					deg_to_rad(kuty[k])])


var calls := 0


func _process_modification_with_delta(_delta: float) -> void:
	_modify()


func _modify() -> void:
	calls += 1
	var skel := get_skeleton()
	if skel == null:
		return
	for c: Array in _curl:
		var b: int = c[0]
		skel.set_bone_pose_rotation(b, skel.get_bone_pose_rotation(b)
				* Quaternion(c[1] as Vector3, c[2] as float))
	if _up_i != -1:
		_shield_arm(skel)


func _aim(skel: Skeleton3D, bone: int, child: int, want: Vector3) -> void:
	var t := skel.get_bone_global_pose(bone)
	var cur := (skel.get_bone_global_pose(child).origin - t.origin).normalized()
	var q := Quaternion(cur, want.normalized())
	skel.set_bone_global_pose(bone, Transform3D(Basis(q) * t.basis, t.origin))


func _shield_arm(skel: Skeleton3D) -> void:
	var left := -_right
	_aim(skel, _up_i, _lo_i, _fwd * SHIELD_UPPER.x + _up * SHIELD_UPPER.y
			+ left * SHIELD_UPPER.z)
	_aim(skel, _lo_i, _hand_i, _fwd * SHIELD_FORE.x + _up * SHIELD_FORE.y
			+ _right * SHIELD_FORE.z)
	if _shield == null:
		return
	var elbow := skel.get_bone_global_pose(_lo_i).origin
	var wrist := skel.get_bone_global_pose(_hand_i).origin
	var dov := elbow.distance_to(wrist)
	var c := elbow.lerp(wrist, SHIELD_AT) + _fwd * dov * SHIELD_OUT + left * dov * SHIELD_LEFT
	# лице щита (−Z речі) — уперед; верх щита — угору
	var z := -_fwd
	var y := (_up - z * _up.dot(z)).normalized()
	var x := y.cross(z).normalized()
	_shield.transform = Transform3D(Basis(x, y, z).scaled_local(Vector3.ONE * _shield_scale), c)
