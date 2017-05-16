node {

  puppet.credentials 'pe-access-token'
  def hostaddress = InetAddress.localHost.hostAddress
  def version = env.BUILD_ID
  def puppetMasterAdress = org.jenkinsci.plugins.puppetenterprise.models.PuppetEnterpriseConfig.getPuppetMasterUrl()

  stage('Prepare build environment'){
    checkout scm
    docker.build("rgbank-build-env:latest")
  }

  if(env.BRANCH_NAME != "master") {
    stage('Lint and unit tests') {
      docker.image("rgbank-build-env:latest").inside {
        //sh "bundle install"
        //sh '/usr/local/bin/bundle exec rspec spec/'
      }
    }

    stage('Build and package') {
      artifactoryServer = Artifactory.server 'artifactory'

      buildUploadSpec = """{
        "files": [ {
          "pattern": "rgbank-build-${version}.tar.gz",
          "target": "rgbank-web"
        } ]
      }"""

      devSQLUploadSpec = """{
        "files": [ {
          "pattern": "rgbank.sql",
          "target": "rgbank-web"
        } ]
      }"""

      docker.image("rgbank-build-env:latest").inside {
        sh "/usr/bin/tar -czf rgbank-build-${version}.tar.gz -C src ."
      }

      archive "rgbank-build-${version}.tar.gz"
      archive "rgbank.sql"
      artifactoryServer.upload spec: buildUploadSpec
      artifactoryServer.upload spec: devSQLUploadSpec
    }

    stage("Provision ${env.BRANCH_NAME} environment") {
      docker.image("rgbank-build-env:latest").inside('--user 0:0') {
        withCredentials([
          string(credentialsId: 'aws-key-id', variable: 'AWS_KEY_ID'),
          string(credentialsId: 'aws-access-key', variable: 'AWS_ACCESS_KEY')
        ]) {
          withEnv([
            "FACTER_puppet_master_address=${puppetMasterAdress}",
            "FACTER_branch=${env.BRANCH_NAME}",
            "VCENTER_USER=${VCENTER_USER}",
            "VCENTER_PASSWORD=${VCENTER_PASSWORD}"
          ]) {
            sh "/opt/puppetlabs/bin/puppet apply /rgbank-vsphere-dev-env.pp"
          }
        }
      }
    }

    stage("Deploy to ${env.BRANCH_NAME}") {
      puppet.hiera scope: 'dev', key: 'rgbank-build-version', value: version
      puppet.codeDeploy env.BRANCH_NAME
      puppet.job 'dev', application: 'Rgbank'
    }
  }

  if(env.BRANCH_NAME == "master") {

    stage('Promote to staging') {
      input "Ready to deploy to staging?"
      puppet.hiera scope: 'rgbank-staging', key: 'rgbank-build-version', value: version
      puppet.codeDeploy 'staging'
      puppet.job 'staging', application: 'Rgbank'
    }
  
    stage('Staging acceptance tests') {
      docker.image("rgbank-build-env:latest").inside {
        sh 'echo success'
      }
    }
  
    stage('Promote to production') {
      input "Ready to test deploy to production?"
    }
  
    stage('Noop production run') {
      puppet.hiera scope: 'rgbank-production', key: 'rgbank-build-version', value: version
      puppet.codeDeploy 'production'
      puppet.job 'production', noop: true, application: 'Rgbank'
    }
  
    stage('Deploy to production') {
      input "Ready to deploy to production?"
      puppet.job 'production', concurrency: 40, application: 'Rgbank'
    }
  }
}
