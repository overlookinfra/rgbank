def get_instance_certnames(String resourcesFile) {
  File f = new File(resourcesFile)

  return certnames
}

node {

  // Default all puppet commands to use the Puppet Enterprise RBAC token stored in the 
  // 'pe-access-token' Jenkins credential.
  puppet.credentials 'pe-access-token'

  version = ''
  puppetMasterAddress = org.jenkinsci.plugins.puppetenterprise.models.PuppetEnterpriseConfig.getPuppetMasterUrl()
  puppetMasterIP = "getent ahostsv4 ${puppetMasterAddress}".execute().text.split("\n")[0].split()[0]

  stage('Prepare build environment'){

    // Checkout the code from version control
    checkout scm
    
    // Set the version being deployed to the first six characters of the commit sha
    version = sh(returnStdout: true, script: 'git rev-parse HEAD').trim().take(6)

    // Set Hiera to use this version of the application for the feature branch this pipeline
    // is being run in.
    puppet.hiera scope: env.BRANCH_NAME, key: 'rgbank-build-version', value: version
    
    // Build the Docker image this pipeline will use to run all system commands for
    // testing, building, and provisioning tasks.
    docker.build("rgbank-build-env:latest")

  }

  stage('Lint and unit tests') {

    // Create a Docker container from the image built in the "Prepare build environment" stage.
    //   Use the container to install the neccessary gems and run rspec.
    docker.image("rgbank-build-env:latest").inside {
      sh "bundle install"
      sh '/usr/local/bin/bundle exec rspec spec/'
    }
  }

  if (env.BRANCH_NAME != "master") {
    stage('Build development environment') {

      //  Create a Docker container from the image built in the "Prepare build environment" stage.
      //    Use the container to apply the provisioning manifest to dynamically build the dev instance for 
      //    this branch. If all the dev instances already exist, nothing new will be provisioned.
      docker.image("rgbank-build-env:latest").inside('--user 0:0') {
        withCredentials([

          // Retrieve the AWS access key id and secret and pass it into environment variables
          string(credentialsId: 'aws-key-id', variable: 'AWS_KEY_ID'),
          string(credentialsId: 'aws-access-key', variable: 'AWS_ACCESS_KEY')

        ]) {
          withEnv([

            //  Set some environment variables. Variables prefixed with "FACTER_" will be
            //    turned into Facter facts by Puppet and thus can be used as top-scope variables
            //    in the Puppet manifest. The AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
            //    variables are used by the puppetlabs/aws module to authenticate to AWS.
            "FACTER_puppet_master_address=${puppetMasterAddress.toString()}",
            "FACTER_puppet_master_ip=${puppetMasterIP}",
            "FACTER_branch=${env.BRANCH_NAME}",
            "FACTER_build=${env.BUILD_NUMBER}",
            "AWS_ACCESS_KEY_ID=${AWS_KEY_ID}",
            "AWS_SECRET_ACCESS_KEY=${AWS_ACCESS_KEY}"

          ]) {

            //  Apply the Puppet manifest to provision the AWS infrastructure. Save the resources
            //    being enforced by the manifest to resources.txt file so we can examine it later.
            //    See the `puppet apply` man page for more information.
            //    https://docs.puppet.com/puppet/latest/man/apply.html
            sh "/opt/puppetlabs/bin/puppet apply /rgbank-aws-dev-env.pp --write-catalog-summary

          }
        }
      }

      certnames = get_instance_certnames("${WORKSPACE}/resources.txt")
      puppet.waitForNodes(certnames) //Wait for the nodes to join the orchestrator
    }

    stage('Deploy app to development environment') {
      //  Groovy 2.4 defaults to GString instead of String
      //    for interpolated strings. We need to convert to String
      app_name = "Rgbank[${env.BRANCH_NAME}]".toString()
      puppet.job 'production', application: app_name
    }

  } else {
    //  We're in a production deployment

    stage('Build and package') {
      artifactoryServer = Artifactory.server 'artifactory'

      buildUploadSpec = """{
        "files": [ {
          "pattern": "rgbank-build-#version#.tar.gz",
          "target": "rgbank-web"
        } ]
      }""".replace("#version#",version)

      devSQLUploadSpec = """{
        "files": [ {
          "pattern": "rgbank.sql",
          "target": "rgbank-web"
        } ]
      }"""

      docker.image("rgbank-build-env:latest").inside {
        sh("/usr/bin/tar -czf rgbank-build-${version}.tar.gz -C src .")
      }

      archive "rgbank-build-${version}.tar.gz"
      archive "rgbank.sql"
      artifactoryServer.upload spec: buildUploadSpec
      artifactoryServer.upload spec: devSQLUploadSpec
    }

    stage('Promote to staging') {
      input "Ready to deploy to staging?"
      puppet.hiera scope: 'staging', key: 'rgbank-build-version', value: version
      puppet.hiera scope: 'staging', key: 'rgbank-build-source-type', value: 'artifactory'
      puppet.job 'production', application: 'Rgbank[staging]'
    }
  
    stage('Staging acceptance tests') {
      docker.image("rgbank-build-env:latest").inside {

        //Do acceptance tests for the application here.
        //  We don't have any so we'll just fake it.
        sh 'echo success'

      }
    }
  
    stage('Promote to production') {
      input "Ready to test deploy to production?"
    }
  
    stage('Noop production run') {
      puppet.hiera scope: 'production', key: 'rgbank-build-version', value: version
      puppet.hiera scope: 'production', key: 'rgbank-build-source-type', value: 'artifactory'
      puppet.job 'production', noop: true, application: 'Rgbank[production]'
    }
  
    stage('Production canary deployment') {
      input "Approve for production canary deployment?"
      query = """inventory {
                  facts.trusted.extensions.pp_application = "rgbank" and
                  facts.trusted.extensions.pp_environment = "production" and
                  facts.trusted.extensions.pp_apptier = "web" and
                  nodes { deactivated is null } limit 2 }"""

      puppet.job 'production', query: query
    }

    stage('Deploy to production') {
      input "Ready to deploy to production?"
      puppet.job 'production', concurrency: 40, application: 'Rgbank[production]'
    }
  }
}
/* vim: set filetype=groovy */
