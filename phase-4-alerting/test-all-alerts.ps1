# Test all ElastAlert2 alert rules by indexing sample documents into Elasticsearch.
# Run this from the repository root using PowerShell.

$esUrl = "http://localhost:9200"
$now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

function Post-Doc {
    param(
        [string]$Index,
        [hashtable]$Body
    )

    $json = $Body | ConvertTo-Json -Depth 10
    Write-Host "Indexing into $Index ..."
    Invoke-RestMethod -Method Post -Uri "$esUrl/$Index/_doc" -ContentType "application/json" -Body $json
}

Write-Host "
=== 1) High HTTP error rate ==="
for ($i = 1; $i -le 10; $i++) {
    Post-Doc -Index "nginx-access-000001" -Body @{
        "@timestamp" = $now
        "http_status_code" = 500
        "request" = "/api/test"
        "client_ip" = "1.2.3.$i"
        "user_agent" = "curl/7.90"
        "method" = "GET"
    }
}

Write-Host "
=== 2) SSH brute force ==="
for ($i = 1; $i -le 5; $i++) {
    Post-Doc -Index "auth-logs-000001" -Body @{
        "@timestamp" = $now
        "ssh_source_ip" = "10.0.0.5"
        "message" = "Failed password for invalid user root"
        "event" = "ssh"
        "host" = "bastion.example.com"
    }
}

Write-Host "
=== 3) Slow response time (P95) ==="
for ($i = 1; $i -le 10; $i++) {
    Post-Doc -Index "app-logs-000001" -Body @{
        "@timestamp" = $now
        "response_time_ms" = 2200
        "service_name" = "checkout"
        "message" = "Response time exceeded threshold"
        "status" = "200"
    }
}

Write-Host "
=== 4) Application error spike ==="
# Add a small baseline, then a larger burst for the same service_name.
Post-Doc -Index "app-logs-000001" -Body @{
    "@timestamp" = $now
    "service_name" = "orders"
    "log_level" = "ERROR"
    "message" = "Baseline error event"
}
Post-Doc -Index "app-logs-000001" -Body @{
    "@timestamp" = $now
    "service_name" = "orders"
    "log_level" = "ERROR"
    "message" = "Baseline error event"
}
for ($i = 1; $i -le 6; $i++) {
    Post-Doc -Index "app-logs-000001" -Body @{
        "@timestamp" = $now
        "service_name" = "orders"
        "log_level" = "ERROR"
        "message" = "Spike error event $i"
    }
}

Write-Host "
=== 5) Disk usage warning ==="
Write-Host "NOTE: The disk usage rule checks the Elasticsearch _size field and currently uses a very high test threshold."
Write-Host "If the rule does not fire, lower the threshold in phase-4-alerting/elastalert2/rules/disk-usage-warning.yml to a test-friendly value like 10000."

# Create a large document to increase size for the disk usage rule test.
$largeMessage = "X" * 200000
Post-Doc -Index "disk-usage-test-000001" -Body @{
    "@timestamp" = $now
    "host" = "node01"
    "message" = $largeMessage
    "type" = "disk_test"
}

Write-Host "
All test documents have been indexed."
Write-Host "Wait for ElastAlert2 to run (1-2 minutes) and then check the configured alert email."
Write-Host "If you want, also run: docker logs elastalert2 --tail 100"
