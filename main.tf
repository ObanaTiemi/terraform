# Configure the Azure provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 2.65"
    }
  }

  required_version = ">= 0.14.9"
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "terraform-mysql983" {
  name     = "cloud-shell-storage-eastus"
  location = "eastus"
}

resource "azurerm_virtual_network" "terraform-mysql-network" {
  name                = "terraform-mysql983"
  address_space       = ["10.0.0.0/16"]
  location            = "eastus"
  resource_group_name = azurerm_resource_group.terraform-mysql983.name
}

resource "azurerm_subnet" "terraform-mysql-subnet" {
  name                 = "subnetmysqltest"
  resource_group_name  = azurerm_resource_group.terraform-mysql983.name
  virtual_network_name = azurerm_resource_group.terraform-mysql983.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_public_ip" "terraform-mysql-pip" {
  name                = "terraform-mysql-pip"
  location            = "eastus"
  resource_group_name = azurerm_resource_group.terraform-mysql983.name
  allocation_method   = "Static"
}

resource "azurerm_network_security_group" "terraform-mysql-nsg" {
  name                = "mysql-nsg"
  location            = "eastus"
  resource_group_name = azurerm_resource_group.terraform-mysql983.name

  security_rule {
    name                       = "mysql"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3306"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "SSH"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "terraform-mysql-ni" {
  name                = "terraform-mysql-ni"
  location            = "eastus"
  resource_group_name = azurerm_resource_group.terraform-mysql983.name

  ip_configuration {
    name                          = "NicConfig"
    subnet_id                     = azurerm_subnet.subnetmysqltest.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.terraform-mysql-pip.id
  }
}

resource "azurerm_network_interface_security_group_association" "terraform-mysql-ga" {
  network_interface_id      = azurerm_network_interface.terraform-mysql-ni.id
  network_security_group_id = azurerm_network_security_group.terraform-mysql-nsg.id
}

data "azurerm_public_ip" "terraform-mysql-pip" {
  name                = azurerm_public_ip.terraform-mysql-pip.name
  resource_group_name = azurerm_resource_group.terraform-mysql983.name
}

resource "azurerm_storage_account" "terraform-mysql-ac" {
  name                     = "storageaccountmterraform"
  resource_group_name      = azurerm_resource_group.terraform-mysql983.name
  location                 = "eastus"
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_linux_virtual_machine" "vmmysqlteste" {
  name                  = "mysqlteste"
  location              = "eastus"
  resource_group_name   = azurerm_resource_group.rgmysqlteste.name
  network_interface_ids = [azurerm_network_interface.nicmysqlteste.id]
  size                  = "Standard_DS1_v2"

  os_disk {
    name                 = "myOsDiskMySQL"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  computer_name                   = "myvm"
  admin_username                  = var.user
  admin_password                  = var.password
  disable_password_authentication = false

  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.samsqlteste.primary_blob_endpoint
  }

  depends_on = [azurerm_resource_group.rgmysqlteste]
}

output "public_ip_address_mysql" {
  value = azurerm_public_ip.publicipmysqlteste.ip_address
}

resource "time_sleep" "wait_30_seconds_db" {
  depends_on      = [azurerm_linux_virtual_machine.vmmysqlteste]
  create_duration = "30s"
}

resource "null_resource" "upload_db" {
  provisioner "file" {
    connection {
      type     = "ssh"
      user     = var.user
      password = var.password
      host     = data.azurerm_public_ip.ip_aula_data_db.ip_address
    }
    source      = "config"
    destination = "/home/azureuser"
  }

  depends_on = [time_sleep.wait_30_seconds_db]
}

resource "null_resource" "deploy_db" {
  triggers = {
    order = null_resource.upload_db.id
  }
  provisioner "remote-exec" {
    connection {
      type     = "ssh"
      user     = var.user
      password = var.password
      host     = data.azurerm_public_ip.ip_aula_data_db.ip_address
    }
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y mysql-server-5.7",
      "sudo mysql < /home/azureuser/config/user.sql",
      "sudo cp -f /home/azureuser/config/mysqld.cnf /etc/mysql/mysql.conf.d/mysqld.cnf",
      "sudo service mysql restart",
      "sleep 20",
    ]
  }
}