extends RefCounted

## Shared quit path for headless suites. Stops pooled WAV playback and waits
## until the audio driver drops those streams, then exits.


static func normal_save_stamp() -> String:
	var path := ProjectSettings.globalize_path(SaveData.PATH)
	if not FileAccess.file_exists(path):
		return "absent"
	return FileAccess.get_sha256(path)


static func save_is_outside_user_dir() -> bool:
	var user_dir := ProjectSettings.globalize_path("user://")
	return not SaveData.save_path.begins_with(user_dir)


static func quiet_quit(host: Node, code: int) -> void:
	if is_instance_valid(Sfx):
		Sfx.release_for_exit()
	# Headless Dummy mixes on its own thread, about an output period apart.
	# process_frame can return before that mix drops AudioStreamPlaybackWAV.
	OS.delay_msec(150)
	if is_instance_valid(Sfx):
		Sfx.finish_release()
	OS.delay_msec(50)
	if is_instance_valid(SaveData):
		SaveData.discard_isolated_save()
	host.get_tree().quit(code)
