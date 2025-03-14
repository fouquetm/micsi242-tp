terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.7.0"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "azurerm" {
  subscription_id = "b7ca1b2b-37c9-49f7-8eb8-df03726a60ba" # peut être remplacé par $env:ARM_SUBSCRIPTION_ID = "10ce0944-5960-42ed-8657-1a8177030014"
  features {}
}
