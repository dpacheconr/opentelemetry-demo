## Metric Alert Policy
resource "newrelic_alert_policy" "metric_alert_policy" {
  name = "Astronomy Service Metric Health"
  incident_preference = "PER_CONDITION_AND_TARGET"
}
