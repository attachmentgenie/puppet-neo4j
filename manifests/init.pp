# == Class: neo4j
#
# Installs Neo4J (http://www.neo4j.com) on RHEL/Ubuntu/Debian from their
# distribution tarballs downloaded directly from their site.
#
# === Parameters
#
# See Readme.md
#
# === Examples
#
#  class { 'neo4j' :
#    version => '2.0.3',
#    edition => 'enterprise',
#  }
#
# See additional examples in the Readme.md file.
#
# === Authors
#
# Amos Wood <amosjwood@gmail.com>
#
# === Copyright
#
# Copyright 2014 Amos Wood, unless otherwise noted.
#
class neo4j (
  $version = '2.1.2',
  $edition = 'community',
  $install_prefix = '/opt/neo4j',

  #service options
  $service_ensure = running,
  $service_enable = true,

  #server options
  $allow_remote_connections = true,
  $jvm_init_memory = '1024',
  $jvm_max_memory = '1024',

  # low-level graph engine options
  $nodestore_memory = undef,
  $relationshipstore_memory = undef,
  $propertystore_memory = undef,
  $propertystore_strings_memory = undef,
  $propertystore_arrays_memory = undef,

  #security
  $auth_ensure = absent,
  $auth_admin_user = undef,
  $auth_admin_password = undef,
  $auth_users = undef,

  #newrelic
  $newrelic_jar_path = undef,

  #high availability settings
  $ha_ensure = absent,
  $ha_server_id = undef,
  $ha_cluster_port = '5001',
  $ha_data_port = '6001',
  $ha_pull_interval = undef,
  $ha_tx_push_factor = undef,
  $ha_tx_push_strategy = undef,
  $ha_allow_init_cluster = true,
  $ha_slave_only = false,
)
{
  $package_name = "neo4j-${edition}-${version}"
  $package_tarball = "${package_name}.tgz"

  if($::kernel != 'Linux') {
    fail('Only Linux is supported at this time.')
  }
  if($version < '2.0.0') {
    fail('Only versions >= 2.0.0 are supported at this time.')
  }
  if($ha_ensure != absent) {
    if(! is_numeric($ha_server_id)) {
      fail('The Server Id value must be specified and must numeric.')
    }
  }

  user { 'neo4j':
    ensure => present,
    gid    => 'neo4j',
    shell  => '/bin/bash',
    home   => $install_prefix,
  }
  group { 'neo4j':
    ensure=>present,
  }

  File {
    owner => 'neo4j',
    group => 'neo4j',
    mode  => '0644',
  }

  Exec {
    path => ['/usr/bin', '/usr/local/bin', '/bin', '/sbin'],
  }

  file { $install_prefix:
    ensure => directory,
  }

  file { "${install_prefix}/data":
    ensure => directory,
  }

  if ! defined(Package['wget']) {
    package { 'wget' : }
  }
  if ! defined(Package['tar']) {
    package { 'tar' : }
  }

  # get the tgz file
  exec { "wget ${package_tarball}" :
    command => "wget \"http://download.neo4j.org/artifact?edition=${edition}&version=${version}&distribution=tarball\" -O ${install_prefix}/${package_tarball}",
    creates => "${install_prefix}/${package_tarball}",
    notify  => Exec["untar ${package_tarball}"],
    require => [Package['wget'], File[$install_prefix]],
  }

  # untar the tarball at the desired location
  exec { "untar ${package_tarball}":
      command     => "tar -xzf ${install_prefix}/${package_tarball} -C ${install_prefix}/; chown neo4j:neo4j -R ${install_prefix}",
      refreshonly => true,
      require     => [Exec ["wget ${package_tarball}"], File[$install_prefix], Package['tar']],
  }

  #install the service
  file {'/etc/init.d/neo4j':
    ensure  => link,
    target  => "${install_prefix}/${package_name}/bin/neo4j",
    require => Exec["untar ${package_tarball}"],
  }

  # Track the configuration files
  file { 'neo4j-server.properties':
    ensure  => file,
    path    => "${install_prefix}/${package_name}/conf/neo4j-server.properties",
    content => template('neo4j/neo4j-server.properties.erb'),
    mode    => '0600',
    require => Exec["untar ${package_tarball}"],
    before  => Service['neo4j'],
    notify  => Service['neo4j'],
  }

  $properties_file = "${install_prefix}/${package_name}/conf/neo4j.properties"

  concat{ $properties_file :
    owner   => 'neo4j',
    group   => 'neo4j',
    mode    => '0644',
    before  => Service['neo4j'],
    notify  => Service['neo4j'],
  }

  concat::fragment{ 'neo4j properties header':
    target  => $properties_file,
    content => template('neo4j/neo4j.properties.concat.1.erb'),
    order   => 01,
  }

  concat::fragment{ 'neo4j properties ha_initial_hosts':
    target  => $properties_file,
    content => 'ha.initial_hosts=',
    order   => 02,
  }

  concat::fragment{ 'neo4j properties footer':
    target  => $properties_file,
    content => "\n\n#End of file\n",
    order   => 99,
  }

  file { 'neo4j-wrapper.conf':
    ensure  => file,
    path    => "${install_prefix}/${package_name}/conf/neo4j-wrapper.conf",
    content => template('neo4j/neo4j-wrapper.conf.erb'),
    mode    => '0600',
    require => Exec["untar ${package_tarball}"],
    before  => Service['neo4j'],
    notify  => Service['neo4j'],
  }

  service{'neo4j':
    ensure  => $service_ensure,
    enable  => $service_enable,
    require => File['/etc/init.d/neo4j'],
  }

  if($auth_ensure) {
    #determine the plugin version
    if($version >= '2.1.0') {
      $authentication_plugin_name = 'authentication-extension-2.1.2-1.0-SNAPSHOT.jar'
    } elsif($version >= '2.0.0') {
      $authentication_plugin_name = 'authentication-extension-2.0.3-1.0-SNAPSHOT.jar'
    } else {
      fail("Authenitcation in version ${version} is not supported. It is only available in version >= 2.0.0.")
    }

    if( ! $auth_admin_user or ! $auth_admin_password) {
      fail('An admin user (auth_admin_user) and password (auth_admin_password) must be set when auth_ensure is true.')
    }

    file { 'authentication-extension' :
      ensure  => file,
      path    => "${install_prefix}/${package_name}/plugins/${authentication_plugin_name}",
      source  => "puppet:///modules/neo4j/${authentication_plugin_name}",
      notify  => Service['neo4j'],
      require => Exec["untar ${package_tarball}"],
    }

    # Track the user management files
    file { 'createNeo4jUser.sh':
      ensure  => file,
      path    => "${install_prefix}/${package_name}/bin/createNeo4jUser",
      source  => 'puppet:///modules/neo4j/createNeo4jUser.sh',
      mode    => '0755',
      require => Exec["untar ${package_tarball}"],
    }
    file { 'updateNeo4jUser.sh':
      ensure  => file,
      path    => "${install_prefix}/${package_name}/bin/updateNeo4jUser",
      source  => 'puppet:///modules/neo4j/updateNeo4jUser.sh',
      mode    => '0755',
      require => Exec["untar ${package_tarball}"],
    }
    file { 'removeNeo4jUser.sh':
      ensure  => file,
      path    => "${install_prefix}/${package_name}/bin/removeNeo4jUser",
      source  => 'puppet:///modules/neo4j/removeNeo4jUser.sh',
      mode    => '0755',
      require => Exec["untar ${package_tarball}"],
    }

    if(is_hash($auth_users)) {
      create_resources(neo4j::user, $auth_users)
    }
  }

  $newrelic_dir_ensure = $::neo4j::newrelic_ensure ? {
    present => directory,
    default => absent,
  }

  file { "${install_prefix}/newrelic" :
    ensure => $newrelic_dir_ensure,
    force  => true,
    notify => Service['neo4j'],
  }
}
