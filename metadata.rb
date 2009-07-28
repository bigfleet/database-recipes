maintainer       "Jim Van Fleet"
maintainer_email "jim@jimvanfleet.com"
license          "MIT"
name    "database"
description 'Additional setup on top of mysql::server to ensure security and availability to apps'
depends "mysql::server"
depends "apt"
depends "gems"
