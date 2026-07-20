# Edge module — ingress / identity-aware access for the Zero Trust environment.
#
# Two independent controls, each behind its own toggle:
#   1. enable_waf          -> WAFv2 web ACL (AWS managed rule groups) fronting the ALB.
#   2. identity_aware_auth -> optional Cognito OIDC in front of the app via an
#                            authenticate-cognito ALB listener rule. OFF by default;
#                            the dissertation runs WAF-only at the edge for now, but the
#                            structure is here so identity-aware access can be flipped on
#                            without reworking the module.

locals {
  tags = merge(var.tags, { Component = "edge" })

  managed_rules = {
    common     = "AWSManagedRulesCommonRuleSet"
    bad_inputs = "AWSManagedRulesKnownBadInputsRuleSet"
    sqli       = "AWSManagedRulesSQLiRuleSet"
  }
}

# ---------------------------------------------------------------------------
# WAFv2 web ACL fronting the ALB. AWS managed rule groups cover the common web
# attacks Nuclei will probe.
# ---------------------------------------------------------------------------
resource "aws_wafv2_web_acl" "this" {
  count       = var.enable_waf ? 1 : 0
  name        = "${var.name_prefix}-web-acl"
  description = "Zero Trust ingress protection for Logi-Track"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  dynamic "rule" {
    for_each = local.managed_rules
    content {
      name     = rule.key
      priority = index(keys(local.managed_rules), rule.key) + 1

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = rule.value
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name_prefix}-${rule.key}"
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name_prefix}-web-acl"
    sampled_requests_enabled   = true
  }

  tags = merge(local.tags, { Name = "${var.name_prefix}-web-acl" })
}

resource "aws_wafv2_web_acl_association" "this" {
  count        = var.enable_waf ? 1 : 0
  resource_arn = var.alb_arn
  web_acl_arn  = aws_wafv2_web_acl.this[0].arn
}

# ---------------------------------------------------------------------------
# Identity-aware access (optional, OFF by default) — Cognito OIDC at the edge.
# When enabled, a user pool + hosted-UI domain is provisioned and the ALB
# authenticates every request before forwarding to the app target group.
# ---------------------------------------------------------------------------
resource "aws_cognito_user_pool" "this" {
  count = var.identity_aware_auth ? 1 : 0
  name  = "${var.name_prefix}-user-pool"

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  tags = merge(local.tags, { Name = "${var.name_prefix}-user-pool" })
}

resource "aws_cognito_user_pool_domain" "this" {
  count        = var.identity_aware_auth ? 1 : 0
  domain       = coalesce(var.cognito_domain_prefix, "${var.name_prefix}-auth")
  user_pool_id = aws_cognito_user_pool.this[0].id
}

resource "aws_cognito_user_pool_client" "this" {
  count        = var.identity_aware_auth ? 1 : 0
  name         = "${var.name_prefix}-alb-client"
  user_pool_id = aws_cognito_user_pool.this[0].id

  generate_secret                      = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  callback_urls                        = var.cognito_callback_urls
  supported_identity_providers         = ["COGNITO"]

  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH",
  ]
}

# authenticate-cognito listener rule: forces OIDC login, then forwards to the app.
resource "aws_lb_listener_rule" "cognito_auth" {
  count        = var.identity_aware_auth ? 1 : 0
  listener_arn = var.listener_arn
  priority     = 1

  action {
    type = "authenticate-cognito"
    authenticate_cognito {
      user_pool_arn       = aws_cognito_user_pool.this[0].arn
      user_pool_client_id = aws_cognito_user_pool_client.this[0].id
      user_pool_domain    = aws_cognito_user_pool_domain.this[0].domain
    }
  }

  action {
    type             = "forward"
    target_group_arn = var.target_group_arn
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }
}
