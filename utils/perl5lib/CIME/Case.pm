package CIME::Case;
my $pkg_nm = __PACKAGE__;

use CIME::Base;
use CIME::XML::Files;
use CIME::XML::env_run;
use CIME::XML::ConfigComponent;

my $logger;

our $VERSION = "v0.0.1";

BEGIN{
    $logger = get_logger("CIME::Case");
}

sub new {
    my ($class,$cimeroot, $caseroot) = @_;

    my $this = {};
    bless($this, $class);
    $this->_init(@_);
    return $this;
}

sub _init {
    my ($this,$class, $cimeroot,$caseroot) = @_;

    $this->SetValue('CIMEROOT',$cimeroot);

    $this->InitCaseXML();

#  $this->SUPER::_init($bar, $baz);
    # Nothing to do here
}

sub InitCaseXML{
    my($this) = @_;

    my $caseroot = $this->GetValue('CASEROOT');
    if(defined ($caseroot)){
	$caseroot = $this->GetResolvedValue($caseroot);
	$this->{env_run} = CIME::XML::env_run->new($this->GetValue('CIMEROOT'), $caseroot."/env_run.xml");
    }
}

sub SetValue {
    my($this,$id,$value) = @_;
    $this->{$id}=$value;
}

sub GetValue {
    my($this,$id, $attribute, $name) = @_;
    my $val;
    if(defined $this->{$id}){
	$val =  $this->{$id};
    }else{
	foreach my $hkey (keys %$this){
	    my $tref = ref ($this->{$hkey});
	    if(ref( $this->{$hkey}) =~ "CIME::XML"){
		$val =  $this->{$hkey}->GetValue($id, $attribute, $name);
	    }
	}
    }
    return $val;
}

sub GetResolvedValue {
    my($this, $val) = @_;

#find and resolve any variable references.    
    my @cnt = $val =~ /\$/g;
    
    for(my $i=0; $i<= $#cnt; $i++){
	if($val =~ /^[^\$]*\$([^\$\}\/]+)/){
	    my $var = $1;
	    my $rvar = $this->GetValue($var);
	    $val =~ s/\$$var/$rvar/;
	}
    }
    
    return $val;

}


sub configure {
    my($this) = @_;

    $this->InitCaseXML();

    $this->{files} = CIME::XML::Files->new($this);

    my $compset_files = $this->{files}->GetValues("COMPSETS_SPEC_FILE","component");

# Find the compset longname and target component
    my $target_comp;
    foreach my $comp (keys %$compset_files){
	my $file = $this->GetResolvedValue($compset_files->{$comp});

# does config_comp need to be part of the object or can it be a local?
#	$this->{"config_$comp"} = CIME::XML::ConfigComponent->new($file);
	my $compset = CIME::XML::ConfigComponent->new($file)->CompsetMatch($this->GetValue("COMPSET"));
	if(defined $compset){
	    $logger->info("Found compset $compset");
	    $this->SetValue("COMPSET",$compset);
	    $target_comp = $comp;
	    last;
	}

    }
    if(!defined $target_comp){
	$logger->logdie("Could not find a compset match for ".$this->GetValue("COMPSET"));
    }

    $this->Compset_Components();


# Fix this, we shouldn't need to hardcode these nor be required to have all of these components
# nor should they be order dependent
    my @components = qw(DRV ATM LND ICE OCN ROF GLC WAV);

    foreach my $comp (@components){
	my $file;
	my $compcomp = shift @{$this->{compset_components}};
	if($comp eq "DRV"){
	    $file = $this->{files}->GetValue('CONFIG_'.$comp.'_FILE');
	}else{
	    print "For $compcomp\n";
	    $file = $this->{files}->GetValue('CONFIG_'.$comp.'_FILE', "component", $compcomp );
	}
	$file = $this->GetResolvedValue($file);

	my $configcomp = CIME::XML::ConfigComponent->new($file);

	
	$this->{env_run}->AddElementsByGroup($configcomp);
	last;
    }

    $this->{env_run}->write();



#    my $grids_file = $this->GetValue('GRIDS_SPEC_FILE');

#    $this->{grid_file} = CIME::XML::Grids->new($grids_file);
    
#    $this->SetValue("GRID", $this->getGridLongname());


    
    print Dumper($this);
    
}



sub Compset_Components
{
    my($this) = @_;
    my $compset_longname = $this->GetValue("COMPSET");
    
    my @elements = split /_/, $compset_longname;

# add the driver explicitly - may need to change this if we have more than one.
    push (@{$this->{compset_components}}, 'drv');

    foreach my $element (@elements){
	next if($element =~ /^\d+$/); # ignore the initial date
	my @element_components = split /%/, $element;
	my $component = lc $element_components[0];
	if ($component =~ m/\d+/) {
	    $component =~ s/\d//g;
	}
	push (@{$this->{compset_components}}, $component);
    }	
}





1;

=head1 NAME

CIME::NAME a module to do this in perl

=head1 SYNOPSIS

  use CIME::NAME;

  why??


=head1 DESCRIPTION

CIME::Name is a perl module to ...
       
A more complete description here.

=head2 OPTIONS

The following optional arguments are supported, passed in using a 
hash reference after the required arguments to ->new()

=over 4

=item loglevel

Sets the level of verbosity of this module, five levels are available:

=over 4

=item DEBUG (most verbose)

=item INFO  (default) 

=item WARN  (reason for concern but no error)

=item ERROR (non-fatal errors should be rare)

=item FATAL (least verbose)  

=back

=item another option

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

