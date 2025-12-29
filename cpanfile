# PAGI::OpenAPI dependencies
# Install with: cpanm --installdeps .

requires 'perl', '5.018';

# PAGI framework (required)
requires 'PAGI', '0.001011';

# Core async framework
requires 'Future::AsyncAwait', '0.66';

# OpenAPI validation
requires 'OpenAPI::Modern', '0.089';
requires 'Plack', '1.0050';

# YAML parsing for schema files
requires 'YAML::PP', '0.038';

# JSON handling
requires 'JSON::MaybeXS', '1.004003';

# Utilities
requires 'Module::Load', '0.36';
requires 'Scalar::Util', '1.63';

# Testing
on 'test' => sub {
    requires 'Test2::V0', '0.000159';
};

# Development
on 'develop' => sub {
    requires 'Dist::Zilla', '6.030';
    requires 'Dist::Zilla::Plugin::MetaJSON';
    requires 'Dist::Zilla::Plugin::MetaResources';
    requires 'Dist::Zilla::Plugin::Prereqs::FromCPANfile';
};
