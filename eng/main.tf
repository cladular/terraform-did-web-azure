provider "azurerm" {
  features {}
}

provider "cloudflare" {
}

data "cloudflare_zones" "this" {
  filter {
    name = var.zone_name
  }
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${var.deployment_name}-${var.location}"
  location = var.location
}

resource "random_string" "this" {
  length  = 24
  special = false
  upper   = false
}

resource "azurerm_storage_account" "this" {
  name                     = random_string.this.result
  resource_group_name      = azurerm_resource_group.this.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  static_website {}
}

resource "azurerm_cdn_profile" "this" {
  name                = "cdn-${var.deployment_name}-${var.location}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "Standard_Microsoft"
}

resource "azurerm_cdn_endpoint" "this" {
  name                          = "endpoint-${var.deployment_name}-${var.location}"
  profile_name                  = azurerm_cdn_profile.this.name
  location                      = azurerm_resource_group.this.location
  resource_group_name           = azurerm_resource_group.this.name
  origin_host_header            = azurerm_storage_account.this.primary_web_host
  querystring_caching_behaviour = "IgnoreQueryString"

  origin {
    name      = var.deployment_name
    host_name = azurerm_storage_account.this.primary_web_host
  }
}

resource "cloudflare_record" "this" {
  zone_id = data.cloudflare_zones.this.zones[0].id
  name    = var.subdomain
  value   = azurerm_cdn_endpoint.this.fqdn
  type    = "CNAME"
  ttl     = 1
  proxied = false
}

resource "azurerm_cdn_endpoint_custom_domain" "this" {
  name            = "endpoint-doain-${var.deployment_name}-${var.location}"
  cdn_endpoint_id = azurerm_cdn_endpoint.this.id
  host_name       = cloudflare_record.this.hostname

  cdn_managed_https {
    certificate_type = "Dedicated"
    protocol_type    = "ServerNameIndication"
  }
}

resource "azurerm_storage_blob" "root" {
  name                   = ".well-known/did.json"
  storage_account_name   = azurerm_storage_account.this.name
  storage_container_name = "$web"
  type                   = "Block"
  content_type           = "application/json"
  source_content = templatefile(var.root_doc, {
    domain = cloudflare_record.this.hostname
  })
}

resource "azurerm_storage_blob" "subdocs" {
  for_each = var.sub_docs

  name                   = "${each.value.route}/did.json"
  storage_account_name   = azurerm_storage_account.this.name
  storage_container_name = "$web"
  type                   = "Block"
  content_type           = "application/json"
  source_content = templatefile(each.value.doc, {
    domain = cloudflare_record.this.hostname
    route  = replace(each.value.route, "/", ":")
  })
}
