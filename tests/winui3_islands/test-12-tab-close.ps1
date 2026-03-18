param([IntPtr]$Hwnd, [int]$ProcessId = 0)

# Test 12: Tab close button — UIA InvokePattern on the TabView close button
# should close the last remaining tab and therefore exit the app.

$ErrorActionPreference = 'Stop'
$testName = "test-12-tab-close"

if ($ProcessId -eq 0) {
    $pidRef = [uint32]0
    [Win32]::GetWindowThreadProcessId($Hwnd, [ref]$pidRef) | Out-Null
    $ProcessId = [int]$pidRef
}

Test-Assert -Condition ($ProcessId -gt 0) -Message "$testName — resolved target process id"

$elem = Find-GhosttyUIAElement -ProcessId $ProcessId
Test-Assert -Condition ($elem -ne $null) -Message "$testName — UIA AutomationElement obtained"

$closeButton = $null
Wait-Condition -TimeoutMs 5000 -Description "tab close button" -ScriptBlock {
    $script:closeButton = Find-UIAChild -Element $elem -AutomationId "CloseButton"
    return ($script:closeButton -ne $null)
}

Test-Assert -Condition ($closeButton -ne $null) -Message "$testName — found CloseButton via UIA"
Test-Assert -Condition ($closeButton.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button) `
    -Message "$testName — CloseButton exposes Button control type"

$invokePattern = $null
$hasInvoke = $closeButton.TryGetCurrentPattern(
    [System.Windows.Automation.InvokePattern]::Pattern, [ref]$invokePattern)
Test-Assert -Condition $hasInvoke -Message "$testName — CloseButton exposes InvokePattern"

Write-Host "  Invoking tab close button: Name='$($closeButton.Current.Name)' AId='$($closeButton.Current.AutomationId)'" -ForegroundColor DarkGray
Invoke-UIAButton -Button $closeButton

Wait-Condition -TimeoutMs 15000 -Description "Ghostty process exit after last tab close" -ScriptBlock {
    $proc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    return ($null -eq $proc)
}

$remaining = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
Test-Assert -Condition ($null -eq $remaining) -Message "$testName — process exited after closing the last tab"

Write-Host "PASS: $testName — UIA CloseButton invocation closed the last tab and exited the app" -ForegroundColor Green
