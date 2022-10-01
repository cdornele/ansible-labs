provider "azurerm" {
  features {}
  subscription_id = "cce9276e-2838-40b0-8833-7122d2b1d366"
} 

data "azurerm_resource_group" "rg" {
    name = "GTA-SANDBOX"
}

data "http" "myip" {
  url = "http://ipv4.icanhazip.com"
}

data "azurerm_subnet" "pvtsubnet" {
    resource_group_name = data.azurerm_resource_group.rg.name
    virtual_network_name = azurerm_virtual_network.vnet.name
    name = "db"
    depends_on = [
      azurerm_virtual_network.vnet
    ]
}

data "azurerm_subnet" "vmsubnet" {
    resource_group_name = data.azurerm_resource_group.rg.name
    virtual_network_name = azurerm_virtual_network.vnet.name
    name = "app"
    depends_on = [
      azurerm_virtual_network.vnet
    ]
}

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  address_space       = ["10.200.0.0/16"]


  subnet {
    name           = "app"
    address_prefix = "10.200.100.0/24"
  }

  subnet {
    name           = "db"
    address_prefix = "10.200.200.0/24"
  }

  tags = {
    environment = "lab",
    customer = "GTA"
  }
}

resource "azurerm_storage_account" "stg" {
  name                     = "stggtalabcgd28092022"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  account_tier             = "Standard"
  account_replication_type = "LRS"
  tags = {
    environment = "lab",
    customer = "GTA"
  }
}

resource "azurerm_mysql_server" "mysql" {
  name                = "zbx-sql-lab"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name

  administrator_login          = "zbxdbsrvadm"
  administrator_login_password = "8e2yeAR$fq2tNyT#B5c"

  sku_name   = "GP_Gen5_2"
  storage_mb = 102400
  version    = "5.7"

  auto_grow_enabled                 = false
  backup_retention_days             = 7
  geo_redundant_backup_enabled      = false
  infrastructure_encryption_enabled = false
  public_network_access_enabled     = false
  ssl_enforcement_enabled           = true
  ssl_minimal_tls_version_enforced  = "TLS1_2"
  tags = {
    environment = "lab",
    customer = "GTA"
  }
}

resource "azurerm_mysql_database" "db" {
  name                = "zabbixdb"
  server_name         = azurerm_mysql_server.mysql.name
  resource_group_name = data.azurerm_resource_group.rg.name
  charset             = "utf8mb4"
  collation           = "utf8mb4_bin"
}


resource "azurerm_private_endpoint" "pvt" {
  name                = "pvt-mysql-server"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  subnet_id           = data.azurerm_subnet.pvtsubnet.id

  private_service_connection {
    name                           = "pvt-mysql-server-connection"
    private_connection_resource_id = azurerm_mysql_server.mysql.id
    subresource_names              = [ "mysqlServer" ]
    is_manual_connection           = false
  }
  tags = {
    environment = "lab",
    customer = "GTA"
  }
}

resource "azurerm_network_security_group" "nsg" {
    depends_on = [
      azurerm_private_endpoint.pvt,
      azurerm_network_interface.linux-vm-nic
    ]

  name                = "nsg-zabbix"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name

  security_rule {
    name                       = "AllowHTTPandHTTPS"
    description                = "Allow HTTP and HTTPS"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowSSH"
    description                = "Allow SSH"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "${chomp(data.http.myip.body)}/32"
    destination_address_prefix = azurerm_network_interface.linux-vm-nic.private_ip_address
  }

    security_rule {
    name                       = "AllowMYSQL"
    description                = "Allow MYSQL"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3306"
    source_address_prefix      = azurerm_network_interface.linux-vm-nic.private_ip_address
    destination_address_prefix = azurerm_private_endpoint.pvt.private_service_connection[0].private_ip_address
  }
  tags = {
    environment = "lab",
    customer = "GTA"
  }
}

resource "azurerm_subnet_network_security_group_association" "vm-nsg-association" {


  subnet_id                 = data.azurerm_subnet.vmsubnet.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_subnet_network_security_group_association" "db-nsg-association" {


  subnet_id                 = data.azurerm_subnet.pvtsubnet.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_public_ip" "linux-vm-ip" {


  name                = "pip-zabbix-app"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  allocation_method   = "Static"
  
  tags = { 
    environment = "lab",
    customer = "GTA"
  }
}

# Create Network Card for linux VM
resource "azurerm_network_interface" "linux-vm-nic" {

  name                = "zabbix-vm-nic"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  
  ip_configuration {
    name                          = "internal"
    subnet_id                     = data.azurerm_subnet.vmsubnet.id
    private_ip_address_allocation = "Dynamic"
    private_ip_address            = "10.200.100.20" 
    public_ip_address_id          = azurerm_public_ip.linux-vm-ip.id
  }

  tags = { 
    environment = "lab",
    customer = "GTA"
  }
}

# Create Linux VM with linux server
resource "azurerm_linux_virtual_machine" "linux-vm" {

  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  name                  = "zabbix-vm"
  network_interface_ids = [azurerm_network_interface.linux-vm-nic.id]
  size                  = "Standard_D2s_v4"

  source_image_reference {
    offer     = "UbuntuServer"
    publisher = "Canonical"
    sku       = "18_04-lts-gen2"
    version   = "latest"
  }

  os_disk {
    name                 = "zabbix-vm-disk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  computer_name  = "zabbix-vm"
  admin_username = "cbotlocal"
  admin_password = "8e2yeAR$fq2tNyT#B5c"


  disable_password_authentication = false

  tags = {
    environment = "lab",
    customer = "GTA"
  }
}

output "public_ip" {
  value = azurerm_public_ip.linux-vm-ip.ip_address
}