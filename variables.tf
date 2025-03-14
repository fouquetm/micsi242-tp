variable "resource_group_name" {
  description = "The name of the resource group in which the resources will be created."
  type        = string
}

variable "location" {
  type = string
}

variable "short_name_location" {
  type = string
}

variable "project_name" {
    description = "The name of the project."
    type        = string
}

variable "vnet_address_space" {
  description = "The address space that is used the virtual network."
  type        = list(string)
}

variable "subnet_capp_address_space" {
  description = "The address space that is used the subnet for the CAPP."
  type        = list(string)
}

variable "subnet_mssql_address_space" {
  description = "The address space that is used the subnet for the MSSQL."
  type        = list(string)
}

variable "subnet_web_address_space" {
  description = "The address space that is used the subnet for the Web App VNet Integration."
  type        = list(string)
}

variable "subnet_endpoints_address_space" {
  description = "The address space that is used the subnet for the Private Endpoints."
  type        = list(string)
}

variable "mssql_username" {
  description = "The username for the MSSQL."
  type        = string
}

variable "dns_zone_name" {
  type = string
}

variable "container_registry_username" {
  type = string
  sensitive = true
}

variable "container_registry_password" {
  type = string
  sensitive = true
}

variable "container_registry_server" {
  type = string
  sensitive = true
}