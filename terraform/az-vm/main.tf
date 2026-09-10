terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=5.4.0"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {}
}

# Create a virtual network within the resource group
resource "azurerm_virtual_network" "vm" {
  name                = "vm-network-terraform"
  resource_group_name = "rg-residencia-tech"
  location            = "East US 2"
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "vm" {
  name                 = "internal"
  resource_group_name  = "rg-residencia-tech"
  virtual_network_name = azurerm_virtual_network.vm.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_public_ip" "vm" {
  name                = "vm_public_ip"
  location            = "East US 2"
  resource_group_name = "rg-residencia-tech"
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "vm" {
  name                = "vm-nic"
  location            = "East US 2"
  resource_group_name = "rg-residencia-tech"

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vm.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm.id
  }
}

resource "azurerm_linux_virtual_machine" "vm" { 
    name = "minha-vm-terraform" 
    size = "Standard_D2s_v3"
    resource_group_name = "rg-residencia-tech"
    location            = "East US 2"
    admin_username = "azureuser"
    network_interface_ids = [
        azurerm_network_interface.vm.id
    ]

    admin_ssh_key {
        username   = "azureuser"
        public_key = file("~/.ssh/id_rsa.pub")
    }

    os_disk {
        caching              = "ReadWrite"
        storage_account_type = "Standard_LRS"
    }

    source_image_reference {
        publisher = "Canonical"
        offer     = "0001-com-ubuntu-server-jammy"
        sku       = "22_04-lts"
        version   = "latest"
    }
}
