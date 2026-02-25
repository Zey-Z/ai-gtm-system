# AI GTM System - Webhook Test Script
# Run: powershell -ExecutionPolicy Bypass -File tests/test-webhook.ps1

$webhookUrl = "http://localhost:5678/webhook/lead-intake"

Write-Host "=== AI GTM System Test Suite ===" -ForegroundColor Cyan
Write-Host ""

# Test 1: High-score lead (should sync to HubSpot + Slack)
Write-Host "[Test 1] High-score lead (score >= 70)" -ForegroundColor Yellow
$body1 = '{"lead_text":"We are TechStartup Inc, interested in your enterprise AI solution. I am Sarah Chen, email sarah.chen@techstartup.com. Our budget is around $75000, hoping to start within two weeks."}'
try {
    $response = Invoke-WebRequest -Uri $webhookUrl -Method POST -ContentType "application/json" -Body $body1
    Write-Host "  Status: $($response.StatusCode) - $($response.Content)" -ForegroundColor Green
} catch {
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

Start-Sleep -Seconds 5

# Test 2: Low-score lead (should NOT sync to HubSpot)
Write-Host "[Test 2] Low-score lead (score < 70)" -ForegroundColor Yellow
$body2 = '{"lead_text":"Hi, I want to learn more about your product. Can we chat sometime?"}'
try {
    $response = Invoke-WebRequest -Uri $webhookUrl -Method POST -ContentType "application/json" -Body $body2
    Write-Host "  Status: $($response.StatusCode) - $($response.Content)" -ForegroundColor Green
} catch {
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

Start-Sleep -Seconds 5

# Test 3: Idempotency test (re-submit same data)
Write-Host "[Test 3] Idempotency test (duplicate submission)" -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri $webhookUrl -Method POST -ContentType "application/json" -Body $body1
    Write-Host "  Status: $($response.StatusCode) - $($response.Content)" -ForegroundColor Green
} catch {
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

Start-Sleep -Seconds 5

# Test 4: Missing/minimal input
Write-Host "[Test 4] Minimal input" -ForegroundColor Yellow
$body4 = '{"lead_text":"Hello"}'
try {
    $response = Invoke-WebRequest -Uri $webhookUrl -Method POST -ContentType "application/json" -Body $body4
    Write-Host "  Status: $($response.StatusCode) - $($response.Content)" -ForegroundColor Green
} catch {
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

Write-Host "=== Tests Complete ===" -ForegroundColor Cyan
Write-Host "Check n8n execution log and database for results."
