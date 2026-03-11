$base = "$env:LOCALAPPDATA\Pub\Cache\hosted\pub.dev\pencil_field-0.4.10\lib\src"
Get-Content "$base\controller.dart" | Out-File -FilePath "pkg_controller.txt" -Encoding utf8
Get-Content "$base\drawing.dart" | Out-File -FilePath "pkg_drawing.txt" -Encoding utf8
Get-Content "$base\paint.dart" | Out-File -FilePath "pkg_paint.txt" -Encoding utf8
Write-Host "Done"
