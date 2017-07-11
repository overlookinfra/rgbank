FROM puppet/puppet-agent-centos:latest

RUN /opt/puppetlabs/bin/puppet module install puppetlabs-aws && \
    /opt/puppetlabs/bin/puppet module install puppetlabs/image_build && \
    /opt/puppetlabs/puppet/bin/gem install aws-sdk-core aws-sdk-resources retries

COPY rgbank-aws-dev-env.pp /
