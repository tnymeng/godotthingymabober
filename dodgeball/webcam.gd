class_name Webcam
extends RefCounted
## Takes a photo with the computer's camera.
##
## Godot's own camera support (CameraServer) is not implemented on Windows,
## so this runs a small PowerShell script that uses Windows' built-in camera
## API (Windows.Media.Capture) to save one JPG, then loads it. It runs in the
## background: start() returns straight away, poll is_busy(), then call
## take_image(). Windows only. The camera takes about 2 seconds to switch on,
## so it is started straight away and the photo is taken at the `delay` time
## (at least 0.3 s after it is on, so the exposure has settled).

const PHOTO_DIR := "user://photos"

const SCRIPT := """param([string]$Dir, [string]$Name, [long]$At = 0)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$methods = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 }
$asTaskOp = $methods | Where-Object { $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } | Select-Object -First 1
$asTaskAction = $methods | Where-Object { $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction' } | Select-Object -First 1
function Await($op, [Type]$type) { $t = $asTaskOp.MakeGenericMethod($type).Invoke($null, @($op)); $t.Wait() | Out-Null; $t.Result }
function AwaitAction($op) { $t = $asTaskAction.Invoke($null, @($op)); $t.Wait() | Out-Null }
[Windows.Media.Capture.MediaCapture, Windows.Media.Capture, ContentType = WindowsRuntime] | Out-Null
[Windows.Media.MediaProperties.ImageEncodingProperties, Windows.Media.MediaProperties, ContentType = WindowsRuntime] | Out-Null
[Windows.Storage.StorageFolder, Windows.Storage, ContentType = WindowsRuntime] | Out-Null
$cap = New-Object Windows.Media.Capture.MediaCapture
$settings = New-Object Windows.Media.Capture.MediaCaptureInitializationSettings
$settings.StreamingCaptureMode = [Windows.Media.Capture.StreamingCaptureMode]::Video
AwaitAction ($cap.InitializeAsync($settings))
$wait = $At - [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
Start-Sleep -Milliseconds ([Math]::Max([long]300, $wait))
$folder = Await ([Windows.Storage.StorageFolder]::GetFolderFromPathAsync($Dir)) ([Windows.Storage.StorageFolder])
$file = Await ($folder.CreateFileAsync($Name, [Windows.Storage.CreationCollisionOption]::ReplaceExisting)) ([Windows.Storage.StorageFile])
AwaitAction ($cap.CapturePhotoToStorageFileAsync([Windows.Media.MediaProperties.ImageEncodingProperties]::CreateJpeg(), $file))
$cap.Dispose()
"""

var _pid: int = -1
var _file: String = ""


## Is a camera available to try? (Windows only.)
static func supported() -> bool:
	return OS.get_name() == "Windows"


## Take a photo saved as `name` (e.g. "p1.jpg") `delay` seconds from now.
## Returns false if it couldn't start (not Windows, or a photo is already
## being taken).
func start(name: String, delay: float = 0.0) -> bool:
	if not supported() or is_busy():
		return false
	DirAccess.make_dir_recursive_absolute(PHOTO_DIR)
	# Windows' storage API only accepts backslashes.
	var dir := ProjectSettings.globalize_path(PHOTO_DIR).replace("/", "\\")
	var script_path := dir + "\\take_photo.ps1"
	var f := FileAccess.open(script_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(SCRIPT)
	f.close()
	_file = dir + "\\" + name
	if FileAccess.file_exists(_file):
		DirAccess.remove_absolute(_file)
	_pid = OS.create_process("powershell.exe", [
			"-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden",
			"-ExecutionPolicy", "Bypass", "-File", script_path,
			"-Dir", dir, "-Name", name, "-At", str(int(Time.get_unix_time_from_system() * 1000.0 + delay * 1000.0))])
	return _pid > 0


func is_busy() -> bool:
	return _pid > 0 and OS.is_process_running(_pid)


## The photo once it's done, or null if it failed (no camera, camera in use,
## or blocked in Windows' camera privacy settings).
func take_image() -> Image:
	_pid = -1
	if _file == "" or not FileAccess.file_exists(_file):
		return null
	var img := Image.load_from_file(_file)
	if img == null or img.is_empty():
		return null
	return img


## Turn a photo into a round character picture: the centre square, mirrored
## like a selfie, cut to a circle with a rim in the player's colour.
## `top_to_right` turns it so the top of the head points right, the way the
## character sprites are drawn (they're rotated to face the way the player is
## facing).
static func make_circle(photo: Image, rim: Color, top_to_right: bool, size: int = 160) -> ImageTexture:
	var img := photo.duplicate() as Image
	img.convert(Image.FORMAT_RGBA8)
	var side := mini(img.get_width(), img.get_height())
	img = img.get_region(Rect2i((img.get_width() - side) / 2, (img.get_height() - side) / 2, side, side))
	img.resize(size, size, Image.INTERPOLATE_BILINEAR)
	img.flip_x()
	if top_to_right:
		img.rotate_90(CLOCKWISE)
	var c := (size - 1) * 0.5
	var r := size * 0.5
	var rim_width := size * 0.07
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length()
			if d > r:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
			elif d > r - 1.0:
				img.set_pixel(x, y, Color(rim, r - d)) # soft outer edge
			elif d > r - rim_width:
				img.set_pixel(x, y, rim)
	return ImageTexture.create_from_image(img)
