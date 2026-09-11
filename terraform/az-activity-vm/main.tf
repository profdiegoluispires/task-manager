terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9"
    }
  }
}

provider "azurerm" {
  features {}
  # Registra automaticamente os resource providers usados pela config (ex.:
  # Microsoft.Network, Microsoft.Compute) — necessário em assinaturas novas
  # (como Azure for Students) que ainda não têm esses namespaces habilitados.
  resource_provider_registrations = "extended"
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-task-manager"
  location = "eastus2"
}

# Espera o resource group ficar visível para outros resource providers antes de
# criar recursos dentro dele — evita "Provider produced inconsistent result"/404
# quando o RG acabou de ser (re)criado (já observado nesta assinatura/região).
resource "time_sleep" "wait_rg" {
  depends_on      = [azurerm_resource_group.rg]
  create_duration = "20s"
}

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-task-manager"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  address_space       = ["10.0.0.0/16"]
  depends_on          = [time_sleep.wait_rg]
}

# Mesma proteção de propagação, agora entre a VNet e a subnet dela.
resource "time_sleep" "wait_vnet" {
  depends_on      = [azurerm_virtual_network.vnet]
  create_duration = "20s"
}

resource "azurerm_subnet" "subnet" {
  name                 = "subnet-task-manager"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
  depends_on           = [time_sleep.wait_vnet]
}

resource "azurerm_public_ip" "public_ip" {
  name                = "pip-task-manager"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  allocation_method   = "Static"
  sku                 = "Standard"
  depends_on          = [time_sleep.wait_rg]
}

resource "azurerm_network_security_group" "nsg" {
  name                = "nsg-task-manager"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  depends_on          = [time_sleep.wait_rg]
}

resource "azurerm_network_security_rule" "allow_http" {
  name                        = "allow-task-manager-http"
  resource_group_name         = azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.nsg.name
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "3000"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
}

# Espera a subnet ficar visível para outros resource providers antes de criar a
# NIC — a API do Azure às vezes confirma a criação da subnet antes dela se
# propagar, e a NIC falha com "InvalidResourceReference" se criada logo em
# seguida (já observado 2x nesta assinatura/região).
resource "time_sleep" "wait_subnet" {
  depends_on      = [azurerm_subnet.subnet]
  create_duration = "30s"
}

resource "azurerm_network_interface" "nic" {
  name                = "nic-task-manager"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  depends_on          = [time_sleep.wait_subnet]

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.public_ip.id
  }
}

resource "azurerm_network_interface_security_group_association" "nic_nsg" {
  network_interface_id     = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# Gerada automaticamente para satisfazer o admin_ssh_key exigido pela VM —
# não depende de o usuário já ter uma chave em ~/.ssh, e não é necessária para
# operar a aplicação, já que o custom_data faz todo o setup sozinho no boot.
resource "tls_private_key" "vm_ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "azurerm_linux_virtual_machine" "task_manager_vm" {
  name                  = "task-manager-vm"
  resource_group_name   = azurerm_resource_group.rg.name
  location              = azurerm_resource_group.rg.location
  # Fora da família B (burstable) — os SKUs B parecem ser o alvo específico da
  # restrição de capacidade nesta assinatura estudantil (B1s/B1ms/B2s falharam
  # todos). D2s_v3 é uso geral, com disponibilidade historicamente maior.
  size                  = "Standard_D2s_v3"
  admin_username        = "azureuser"
  network_interface_ids = [azurerm_network_interface.nic.id]

  admin_ssh_key {
    username   = "azureuser"
    public_key = tls_private_key.vm_ssh.public_key_openssh
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

  # Executado automaticamente no primeiro boot (cloud-init) — dispensa SSH manual
  # para instalar e iniciar a aplicação. Mesmo script usado na VM do GCP: instala
  # Docker e sobe app + banco (postgres:15) via docker-compose.yml do repositório.
  custom_data = filebase64("${path.module}/../../scripts/deploy-vm.sh")
}
