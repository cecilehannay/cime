package CIME::Name;
my $pkg_nm = __PACKAGE__;

use CIME::Base;
use Log::Log4perl;
my $logger;

our $VERSION = "v0.0.1";

BEGIN{
    $logger = Log::Log4perl::get_logger();
}

sub new {
    my ($class, $file) = @_;
    my $this = {};
   

 
    bless($this, $class);
    $this->_init(@_);
    return $this;
}

sub _init {
    my ($this, $file) = @_;
#  $this->SUPER::_init($bar, $baz);
    # Nothing to do here
}






1;
    
__END__

=head1 NAME

CIME::NAME a module to do this in perl


=head1 SYNOPSIS

  use CIME::NAME;

  why??


=head1 DESCRIPTION

CIME::Name is a perl module to ...
       
A more complete description here.

=head2 OPTIONS

General description of options

=over 4

=item loglevel

Sets the level of verbosity of this module, five levels are available 
=over 4 

=item DEBUG (most verbose)
=item INFO  (default)
=item WARN  (Show only messages at this level or higher)
=iten ERROR (Error messages that are not fatal (rare))
=item FATAL (Error messages that are accompained by a program halt.)

=back

=head1 SEE ALSO

=head1 AUTHOR AND CREDITS

{name and e-mail}

{Other credits}

=head1 COPYRIGHT AND LICENSE


This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut
__END__
