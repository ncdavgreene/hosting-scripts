#!/bin/bash
# cloudflare_failover.sh
#
# This script monitors your primary server via a health check URL.
# If the primary server is down, it updates your Cloudflare DNS A record
# to point to the failover server. When the primary server is back up, it
# switches the record back to the primary IP.
#
# Required variables:
#   CF_API_KEY    - Your Global API Key from Cloudflare.
#   CF_API_EMAIL  - The email address associated with your Cloudflare account.
#   CF_ZONE_ID    - Your Cloudflare Zone ID for your domain.
#   CF_RECORD_ID  - The DNS record ID of the A record to update.
#   DOMAIN        - Your domain name (that you want to update the A record for).
#   MAIN_IP       - The IP address of your primary server.
#   FAILOVER_IP   - The IP address of your failover server.
#   HEALTHCHECK_URL - The URL used to check the health of your primary server.
#
# Customize these variables below:

CF_API_KEY="your_api_key_here"                # e.g., "abcd1234..."
CF_API_EMAIL="your_email@example.com"         # e.g., "your_email@example.com"
CF_ZONE_ID="your_zone_id_here"                # e.g., "e5f6g7h8..."
CF_RECORD_ID="your_record_id_here"            # e.g., "i9j0k1l2..."
DOMAIN="yourdomain.com"                       # e.g., "example.com"
MAIN_IP="192.168.1.100"                       # Primary server IP
FAILOVER_IP="34.56.78.90"                     # Failover server IP
HEALTHCHECK_URL="https://yourdomain.com/health" # URL to check (adjust the endpoint)

# Optional: DNS resolver to query the current DNS record (Cloudflare recommends 1.1.1.1)
DNS_RESOLVER="1.1.1.1"

# Function: Update the DNS record using Cloudflare's Global API Key
update_dns() {
  local new_ip="$1"
  echo "$(date '+%Y-%m-%d %H:%M:%S') - Updating DNS record to: ${new_ip}"
  response=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${CF_RECORD_ID}" \
    -H "X-Auth-Email: ${CF_API_EMAIL}" \
    -H "X-Auth-Key: ${CF_API_KEY}" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"A\",\"name\":\"${DOMAIN}\",\"content\":\"${new_ip}\",\"ttl\":120,\"proxied\":true}")
  
  # Check for success in the API response
  if echo "$response" | grep -q '"success":true'; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - DNS update successful."
  else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - DNS update failed. Response: $response"
  fi
}

# Function: Check the health of the primary server
check_health() {
  # Always hit the PRIMARY box, even if DNS is on the fail‑over
  curl --silent --fail --max-time 5 \
       --resolve "${DOMAIN}:443:${MAIN_IP}" \
       "https://${DOMAIN}/health" > /dev/null; then
    return 0  # Healthy
  else
    return 1  # Unhealthy
  fi
}

# Function: Get the current IP from DNS for the A record
get_current_dns_ip() {
  response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${CF_RECORD_ID}" \
    -H "X-Auth-Email: ${CF_API_EMAIL}" \
    -H "X-Auth-Key: ${CF_API_KEY}" \
    -H "Content-Type: application/json")
  
  # Extract the "content" field, which contains the actual IP set in the record
  ip=$(echo "$response" | grep -o '"content":"[^"]*"' | cut -d'"' -f4)
  
  echo "$ip"
}

# Main logic
current_dns_ip=$(get_current_dns_ip)
echo "$(date '+%Y-%m-%d %H:%M:%S') - Current DNS IP for ${DOMAIN} is: ${current_dns_ip}"

if check_health; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') - Primary server is healthy."
  # If primary is healthy and DNS doesn't already point to MAIN_IP, update it.
  if [ "$current_dns_ip" != "$MAIN_IP" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - DNS record mismatch, switching back to primary."
    update_dns "$MAIN_IP"
  else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - DNS record already points to primary. No update necessary."
  fi
else
  echo "$(date '+%Y-%m-%d %H:%M:%S') - Primary server appears to be down."
  # If primary is down and DNS doesn't already point to FAILOVER_IP, update it.
  if [ "$current_dns_ip" != "$FAILOVER_IP" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Updating DNS record to failover server."
    update_dns "$FAILOVER_IP"
  else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - DNS record already points to failover. No update necessary."
  fi
fi
