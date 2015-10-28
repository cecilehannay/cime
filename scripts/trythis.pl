#!/user/bin/env perl
BEGIN{
    my $cimeroot = $ENV{CIMEROOT};
    die "CIMEROOT environment variable not set" unless defined $cimeroot;
    die "CIMEROOT directory \"$cimeroot\" not found" unless (-d $cimeroot);
    unshift @INC, "$cimeroot/utils/perl5lib";
    require CIME::Base;
}
use CIME::Base;
#use CIME::XML::Machine;
#use CIME::XML::Components;
#use CIME::XML::Headers;
use CIME::XML::Run;
my %opts;
$opts{loglevel}="INFO";

CIME::Base->getopts(\%opts);

#GetOptions("localopt=s"=>$opts{localopt});

my $level = Log::Log4perl::Level::to_priority($opts{loglevel});
Log::Log4perl->easy_init({level=>$level,
			  layout=>'%m%n'});

my $logger = Log::Log4perl::get_logger();

my $cimeroot = $ENV{CIMEROOT};
#my $machine = CIME::XML::Machine->new({CIMEROOT=>$cimeroot,
#                                                                       MODEL=>"cesm"});
#$machine->read("yellowstone");
#$machine->loadModules();
use Data::Dumper;

my $obj = CIME::XML::Run->new($cimeroot);
$obj->write();






#my $files_config_spec = $components->get('FILES_CONFIG_SPEC');
#print "$files_config_spec\n";
#print Dumper($components);

__END__
=head1 NAME

create_newcase - CIME case generator script

=head1 SYNOPSIS

    create_newcase [options] 
    Options:
       -help             brief help message
       -loglevel <level> set stdout message verbosity
       -model <name>     Specifies target model system.

=head1 OPTIONS
=over 8
=item B<-help>
Prints a brief help message and exits.
=item B<-loglevel>
Can be DEBUG (most verbose), INFO (default), WARN, ERROR, FATAL(least verbose)    
=back
=head1 DESCRIPTION
B<create_newcase> will read the given input file(s) and do something
useful with the contents thereof.
=cut
