# 创建一个VPC，作为容器，装在其他网络资源
resource "alicloud_vpc" "branch_office_vpc" {
  vpc_name   = "LabVPC"
  cidr_block = "172.16.0.0/16"
}

resource "alicloud_vpc" "headquarters_office_vpc" {
  vpc_name   = "LabVPC"
  cidr_block = "172.16.0.0/16"
}

# 使用VPC高阶特性，互联网网关
resource "alicloud_vpc_ipv4_gateway" "branch_office_vpc_igw" {
  ipv4_gateway_name = "LabVPC-IGW"
  vpc_id            = alicloud_vpc.branch_office_vpc.id
  enabled           = "true"
}
resource "alicloud_vpc_ipv4_gateway" "headquarters_office_vpc_igw" {
  ipv4_gateway_name = "LabVPC-IGW"
  vpc_id            = alicloud_vpc.headquarters_office_vpc.id
  enabled           = "true"
}

# 创建2个路由表，公司总部一个、分支办公室一个
resource "alicloud_route_table" "branch_office" {
  description      = "分支办公室"
  vpc_id           = alicloud_vpc.branch_office_vpc.id
  route_table_name = "branch-office"
  associate_type   = "VSwitch"
}

resource "alicloud_route_table" "headquarters_office" {
  description      = "公司总部"
  vpc_id           = alicloud_vpc.headquarters_office_vpc.id
  route_table_name = "headquarters-office"
  associate_type   = "VSwitch"
}

# 创建2个交换机，公司总部一个，分支办公室一个
resource "alicloud_vswitch" "branch_office" {
  vswitch_name = "分支办公室"
  cidr_block   = "172.16.12.0/24"
  vpc_id       = alicloud_vpc.branch_office_vpc.id
  zone_id      = "cn-zhangjiakou-c"
}

resource "alicloud_vswitch" "headquarters_office" {
  vswitch_name = "公司总部"
  cidr_block   = "172.16.11.0/24"
  vpc_id       = alicloud_vpc.headquarters_office_vpc.id
  zone_id      = "cn-zhangjiakou-c"
}

# 把2个交换机和各自的路由表关联起来
resource "alicloud_route_table_attachment" "branch_office" {
  vswitch_id     = alicloud_vswitch.branch_office.id
  route_table_id = alicloud_route_table.branch_office.id
}

resource "alicloud_route_table_attachment" "headquarters_office" {
  vswitch_id     = alicloud_vswitch.headquarters_office.id
  route_table_id = alicloud_route_table.headquarters_office.id
}

# 给两个路由表添加默认路由到互联网网关，后面通过公网IP访问ECS实例，简化运维操作且省钱，不用走跳板机或者NAT网关了
resource "alicloud_route_entry" "branch_office_gw" {
  route_table_id        = alicloud_route_table.branch_office.id
  destination_cidrblock = "0.0.0.0/0"
  nexthop_type          = "Ipv4Gateway"
  nexthop_id            = alicloud_vpc_ipv4_gateway.branch_office_vpc_igw.id
}

resource "alicloud_route_entry" "headquarters_office_gw" {
  route_table_id        = alicloud_route_table.headquarters_office.id
  destination_cidrblock = "0.0.0.0/0"
  nexthop_type          = "Ipv4Gateway"
  nexthop_id            = alicloud_vpc_ipv4_gateway.headquarters_office_vpc_igw.id
}

# 创建一个安全组，附加到ecs实例上，放行所有流量
resource "alicloud_security_group" "branch_office_vpc_open_sg" {
  vpc_id              = alicloud_vpc.branch_office_vpc.id
  security_group_type = "normal"
  name                = "openSG"
  description         = "open to the world"
  inner_access_policy = "Accept"
}

resource "alicloud_security_group" "headquarters_office_vpc_open_sg" {
  vpc_id              = alicloud_vpc.headquarters_office_vpc.id
  security_group_type = "normal"
  name                = "openSG"
  description         = "open to the world"
  inner_access_policy = "Accept"
}

resource "alicloud_security_group_rule" "branch_office_allow_all_traffic" {
  type              = "ingress"
  ip_protocol       = "all"
  policy            = "accept"
  priority          = 1
  security_group_id = alicloud_security_group.branch_office_vpc_open_sg.id
  cidr_ip           = "0.0.0.0/0"
}

resource "alicloud_security_group_rule" "headquarters_office_allow_all_traffic" {
  type              = "ingress"
  ip_protocol       = "all"
  policy            = "accept"
  priority          = 1
  security_group_id = alicloud_security_group.headquarters_office_vpc_open_sg.id
  cidr_ip           = "0.0.0.0/0"
}

# 确定image
data "alicloud_images" "images_ds" {
  owners       = "system"
  name_regex   = "^centos_7"
  os_type      = "linux"
  most_recent  = true
  architecture = "x86_64"
}

# 确定key
data "alicloud_ecs_key_pairs" "work_mac_pro" {
  ids        = ["work-mac-pro"]
  name_regex = "work-mac-pro"
}

# 从2个交换机下分别启动一个ecs实例用作vpn主机
resource "alicloud_instance" "instance_vpn1" {
  security_groups            = [alicloud_security_group.headquarters_office_vpc_open_sg.id]
  vswitch_id                 = alicloud_vswitch.headquarters_office.id
  instance_charge_type       = "PostPaid"
  spot_strategy              = "SpotAsPriceGo"
  instance_type              = "ecs.t5-lc1m1.small"
  internet_charge_type       = "PayByTraffic"
  internet_max_bandwidth_out = 5
  system_disk_size           = max(20, data.alicloud_images.images_ds.images[0].size)
  key_name                   = data.alicloud_ecs_key_pairs.work_mac_pro.names[0]
  system_disk_category       = "cloud_efficiency"
  image_id                   = data.alicloud_images.images_ds.ids[0]
  instance_name              = "vpn1"
  private_ip                 = "172.16.11.1"
  host_name                  = "vpn1"
}

resource "alicloud_instance" "instance_vpn2" {
  security_groups            = [alicloud_security_group.branch_office_vpc_open_sg.id]
  vswitch_id                 = alicloud_vswitch.branch_office.id
  instance_charge_type       = "PostPaid"
  spot_strategy              = "SpotAsPriceGo"
  instance_type              = "ecs.t5-lc1m1.small"
  internet_charge_type       = "PayByTraffic"
  internet_max_bandwidth_out = 5
  system_disk_size           = max(20, data.alicloud_images.images_ds.images[0].size)
  key_name                   = data.alicloud_ecs_key_pairs.work_mac_pro.names[0]
  system_disk_category       = "cloud_efficiency"
  image_id                   = data.alicloud_images.images_ds.ids[0]
  instance_name              = "vpn2"
  private_ip                 = "172.16.12.1"
  host_name                  = "vpn2"
}

# 新增路由把发往VPN对端端点的流量路由到对端网络里的VPN服务器
resource "alicloud_route_entry" "branch_office_tovpn1" {
  route_table_id        = alicloud_route_table.branch_office.id
  destination_cidrblock = "10.200.0.0/30"
  nexthop_type          = "Instance"
  nexthop_id            = alicloud_instance.instance_vpn2.id
}

resource "alicloud_route_entry" "headquarters_office_tovpn2" {
  route_table_id        = alicloud_route_table.headquarters_office.id
  destination_cidrblock = "10.200.0.0/30"
  nexthop_type          = "Instance"
  nexthop_id            = alicloud_instance.instance_vpn1.id
}

# 新增到对端网段的路由
resource "alicloud_route_entry" "branch_office_to_headquarters" {
  route_table_id        = alicloud_route_table.branch_office.id
  destination_cidrblock = "172.16.11.0/24"
  nexthop_type          = "Instance"
  nexthop_id            = alicloud_instance.instance_vpn2.id
}

resource "alicloud_route_entry" "headquarters_office_to_branch" {
  route_table_id        = alicloud_route_table.headquarters_office.id
  destination_cidrblock = "172.16.12.0/24"
  nexthop_type          = "Instance"
  nexthop_id            = alicloud_instance.instance_vpn1.id
}

# 再准备2台用于扮演应用客户端和服务器的机器
resource "alicloud_instance" "mock_server" {
  security_groups            = [alicloud_security_group.headquarters_office_vpc_open_sg.id]
  vswitch_id                 = alicloud_vswitch.headquarters_office.id
  instance_charge_type       = "PostPaid"
  spot_strategy              = "SpotAsPriceGo"
  instance_type              = "ecs.t5-lc1m1.small"
  internet_charge_type       = "PayByTraffic"
  internet_max_bandwidth_out = 5
  system_disk_size           = max(20, data.alicloud_images.images_ds.images[0].size)
  key_name                   = data.alicloud_ecs_key_pairs.work_mac_pro.names[0]
  system_disk_category       = "cloud_efficiency"
  image_id                   = data.alicloud_images.images_ds.ids[0]
  instance_name              = "mock-server"
  private_ip                 = "172.16.11.100"
  host_name                  = "server"
}

resource "alicloud_instance" "mock_client" {
  security_groups            = [alicloud_security_group.branch_office_vpc_open_sg.id]
  vswitch_id                 = alicloud_vswitch.branch_office.id
  instance_charge_type       = "PostPaid"
  spot_strategy              = "SpotAsPriceGo"
  instance_type              = "ecs.t5-lc1m1.small"
  internet_charge_type       = "PayByTraffic"
  internet_max_bandwidth_out = 5
  system_disk_size           = max(20, data.alicloud_images.images_ds.images[0].size)
  key_name                   = data.alicloud_ecs_key_pairs.work_mac_pro.names[0]
  system_disk_category       = "cloud_efficiency"
  image_id                   = data.alicloud_images.images_ds.ids[0]
  instance_name              = "mock-client"
  private_ip                 = "172.16.12.234"
  host_name                  = "client"
}

data "aws_route53_zone" "main" {
  name = "lgypro.com"
}

resource "aws_route53_record" "openvpn_server" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "openvpn"
  type    = "A"
  ttl     = "60"
  records = [alicloud_instance.instance_vpn1.public_ip]
}


# 输出2台vpn服务器的公网地址
output "vpn1_public_ip" {
  value = alicloud_instance.instance_vpn1.public_ip
}

output "vpn2_public_ip" {
  value = alicloud_instance.instance_vpn2.public_ip
}
