#!/usr/bin/env perl 
#==============================================================================
# File:  BatchMaker.pm
# Purpose: Provide a class hierarchy to ease the job of making batch scripts for 
#          each CESM-ported machine.  We have class hierarchy and a factory class
#          to facilitate getting the right BatchMaker class for the appropriate 
#          machine. 
#
#          BatchMaker: This is the base class which contains functionality 
#          common to making batch scripts for every machine. This class should 
#          never be instantiated directly, use BatchFactory for this. 
#
#
#          BatchFactory:  This is the factory class responsible for returning
#          the correct BatchMaker_$machine class . 
#
#          We can have subclasses based on the batch system type, then subclasses
#          of those based on the machine. 
#
#==============================================================================
use strict;
use warnings;

package Batch::BatchMaker;
use Cwd 'getcwd';
use Data::Dumper;
use XML::LibXML;
use Exporter qw(import);
use lib '.';
use Task::TaskMaker;
use Config::envBatch;
#my $cesmRunSuffix = '$config{\'EXEROOT\'}/cesm.exe >> $cesm.log.$LID 2>&1';
my @requiredargs = qw/caseroot case machroot machine cimeroot/;
use Log::Log4perl qw(get_logger);

my $logger;

BEGIN{
    $logger = get_logger();
}

#==============================================================================
#  Class constructor.  We need to know where in the filesystem we are, 
#  so caseroot, case, machroot, machine, cimeroot
#==============================================================================
sub new
{
    my ($class, %params) = @_;
    my $self = {
	case	=> $params{'case'}	|| undef,
	caseroot	=> $params{'caseroot'}	|| undef,
	compiler    => $params{'compiler'}  || undef,
	config	=> $params{'config'}    || undef,
	machine     => $params{'machine'}   || undef,
	cimeroot	=> $params{'cimeroot'}	|| undef,
	machroot    => $params{'machroot'}  || ".",
	mpilib      => $params{'mpilib'}    || undef,
	threaded    => $params{'threaded'}  || undef,
	job => $params{job} || undef,
    };
    $self->{'srcroot'} = $self->{'cimeroot'} if defined $self->{'cimeroot'};

    # make sure that the required args are supplied
    foreach my $reqarg(@requiredargs)
    {
	if(! defined $reqarg)
	{
	    die "The value $reqarg must be passed into the constructor!";
	}
    }
    # set up paths to the template files, this could and should be extracted out somehow??
    $self->{'job_id'} = $self->{'case'};
    if ($self->{'machine'} =~ /pleiades/) { # pleiades jobname needs to be limited to 15 chars
	$self->{'job_id'} = substr( $self->{'job_id'}, 0, 15 );
    }
    $self->{'output_error_path'} = $self->{'case'};
    $self->{'configbatch'} = "$self->{'machroot'}/config_batch.xml";
    $self->{'configmachines'} = "$self->{'machroot'}/config_machines.xml";
    
    # we need ProjectTools. 
    my $cimeroot = "$self->{'cimeroot'}";
    push(@INC, "$cimeroot/utils/per5lib");

    $self->{envBatch} = Config::envBatch->new();
    $self->{envBatch}->read("$self->{caseroot}/env_batch.xml");

    $self->{'cwd'} = Cwd::getcwd();
    bless $self, $class;
    return $self;
}
#==============================================================================
# Do the variable substitution for any variables that need transforms 
# recursively. 
#==============================================================================
sub transformVars()
{
    my $self = shift;
    my $text = shift;
    
    my @lines = split(/\n/, $text);
    foreach my $line(@lines)
    {
        # loop through directive line, replacing each string enclosed with
        # template characters with the necessary values.
        while($line =~ /({{ \w+ }})/)
        {
            my $needstransform = $1;
            my $var = $needstransform;
            $var =~ s/{{ //g;
            $var =~ s/ }}//g;
            #print "needs transform: $needstransform\n";
            #print "var : $var\n";

            if(defined $self->{$var} )
            {
                $line =~ s/$needstransform/$self->{$var}/g;
            }
            
        }
    }
    $text = join("\n", @lines);

    # recursively call this function if we still have things to transform, 
    # otherwise return the transformed text
    if($text =~ /{{ \w+ }}/)
    {
        $self->transformVars($text);
    }
    else
    {
        return $text;
    }
}


#==============================================================================
# Gets the XML::LibXML parser for config_batch.xml, then stash it in the object 
# as a parameter
#==============================================================================
sub getBatchConfigParser()
{
    my $self = shift;
    my $toolsdir = $self->{'caseroot'} . "/Tools";
    if(! defined $self->{'batchparser'})
    {
	chdir $self->{'caseroot'};
	my $batchparser = XML::LibXML->new(no_blanks => 1);
	my $batchconfig = $batchparser->parse_file($self->{'configbatch'});
	$self->{'batchparser'} = $batchconfig->getDocumentElement();
    }
    return $self->{'batchparser'};
}

#==============================================================================
# Gets the XML::LibXML parser for config_batch.xml, then stash it in the object 
# as a parameter
#==============================================================================
sub getConfigMachinesParser()
{
    my $self = shift;
    my $toolsdir = $self->{'caseroot'} . "/Tools";
    if(! defined $self->{'configmachinesparser'})
    {
	chdir $self->{'caseroot'};
	my $configmachinesparser = XML::LibXML->new(no_blanks => 1);
	my $configmachines = $configmachinesparser->parse_file($self->{'configmachines'});
	$self->{'configmachinesparser'} = $configmachines->getDocumentElement();
    }
}

#==============================================================================
# make the actual batch script.  
# get the filename, call the appropriate methods to get: task info, 
# the queue, the walltime, set the project, set the values for the batch
# directives, insert the code to actually run the model based on your machine. 
# Finally, writeBatchScript substitutes the values into the run template, 
# and writes the new batch script into the case root. 
#==============================================================================
sub makeBatchScript()
{
    my $self = shift;
    my $inputfilename = shift;
    my $outputfilename = shift;

    $logger->debug("In makeBatchScript 1");
    if(! -f $inputfilename)
    {
	die "$inputfilename does not exist!";
    }
    
    $self->getBatchSystemTypeForMachine();
    $logger->debug("In makeBatchScript 2");
    $self->setTaskInfo();
    $logger->debug("In makeBatchScript 3");
    $self->setQueue();
    $logger->debug("In makeBatchScript 4");
    $self->setWallTime();
    $logger->debug("In makeBatchScript 5");
    $self->setProject();
    $logger->debug("In makeBatchScript 6");
    $self->setBatchDirectives();
    $logger->debug("In makeBatchScript 7");
    $self->getLtArchiveOptions();
    $logger->debug("In makeBatchScript 8");
    $self->setCESMRun();
    $logger->debug("In makeBatchScript 9");
    $self->writeBatchScript($inputfilename, $outputfilename);
}

#==============================================================================
# get the batch system type for this machine. 
#==============================================================================
sub getBatchSystemTypeForMachine()
{
    my $self = shift;
    my $mach = $self->{'machine'};
    $self->getConfigMachinesParser();
    my $configmachinesparser = $self->{'configmachinesparser'};
    my @batchtypes = $configmachinesparser->findnodes("/config_machines/machine[\@MACH=\'$mach\']/batch_system");

    if(!@batchtypes)
    {
	die "Could not find batch system for machine $self->{'machine'}, aborting";
    }
    $self->{'batch_system'} = $batchtypes[0]->getAttribute('type');
    
}

#==============================================================================
# Get batch directives, optionally setting up the data needed if not already 
# done. 
#==============================================================================
sub getBatchDirectives()
{
    my $self = shift;
    
    if(! defined $self->{'batchdirectives'})
    {

	$self->getBatchSystemTypeForMachine();
	$self->setTaskInfo();
	$self->setQueue();
	$self->setWallTime();
	$self->setProject();
	$self->setBatchDirectives();
    }
    return $self->{'batchdirectives'};

}
#==============================================================================
# Get a particular field of data from the instance data that gets stored 
# in this object.  There should really be a separate BatchData class, but
# this is good enough for now.  
#==============================================================================
sub getField()
{
    my $self = shift;
    my $fieldname = shift;

    $self->getBatchSystemTypeForMachine();
    $self->setTaskInfo();
    $self->setQueue();
    $self->setWallTime();
    $self->setProject();
    my $field = $self->{$fieldname};


    if(defined $field)
    {
        return $field;
    }
    else
    {
        return undef;
    }
}

#==============================================================================
# Get the batch directives for this machine from config_batch.xml, 
#==============================================================================
sub setBatchDirectives()
{
    my $self = shift;
    my $batchparser = $self->getBatchConfigParser();
    my $configmachinesparser = $self->getConfigMachinesParser();
    
    # get the batch directive for this particular queueing system. 

    my @batch_directive = $batchparser->findnodes("/config_batch/batch_system[\@type=\'$self->{'batch_system'}\']/batch_directive");

    if(!@batch_directive)
    {
	die "Cannot find batch directive for the batch system type $self->{'batch_system'}";
    }
    $self->{'batch_directive'} = $batch_directive[0]->textContent();

    my @directives = $batchparser->findnodes("/config_batch/batch_system[\@type=\'$self->{'batch_system'}\' or \@MACH=\'$self->{machine}\']/directives/directive");
    if(!@directives)
    {
	die "could not find any directives for the machine $self->{'machine'}";
    }

    #This should be empty every time this method is called. 
    $self->{'batchdirectives'} = '';

    # iterate through all the directives found.  Get the name attribute and the 
    # text content for each directive. 
    foreach my $directive(@directives)
    {
	
	# For every directive we find, we have to replace what is contained within the double-underscores 
	# with the actual instance variable..
	#

	my $directiveLine = $self->{'batch_directive'} . " ";
	my $dvalue = $directive->textContent();
	my $valueToUse = undef;
	
	# Do the variable transform if necessary. 
        # strip the special characters
	while($dvalue =~ /({{ \w+ }})/)
	{
	    my $matchedString = $1;
	    my $stringToReplace = $matchedString;
	    $stringToReplace =~ s/{{ //g;
	    $stringToReplace =~ s/ }}//g;
	    my $actualValue;
	    
            # If the instance data for the variable doesn't exist, and we have a default, 
            # use the default value we find. 
	    if(! defined $self->{$stringToReplace} && $directive->hasAttribute('default'))
	    {
		$actualValue = $directive->getAttribute('default');
		$directiveLine .= $actualValue;
		$dvalue =~ s/$matchedString/$actualValue/g;
	    }
	    # If we DO have instance data for the variable, and there is no default, use the 
            # instance data. 
	    elsif(! $directive->hasAttribute('default') &&  defined $self->{$stringToReplace})
	    {
		$actualValue = $self->{$stringToReplace};
		$dvalue =~ s/$matchedString/$actualValue/g;
	    }
	    # If we don't have either instance data to use, or a default value we can use, 
            # get rid of the variable entirely. 
	    elsif(! $directive->hasAttribute('default') && ! defined $self->{$stringToReplace})
	    {
		$dvalue = '';
	    }
	}
	# If we have data in the dvalue for the directive, add the directive 
        # to our batchdirectives instance data. 
	if(length($dvalue) > 0)
	{

	    my $directiveLine = $self->{'batch_directive'} . " " . $dvalue;
	    $self->{'batchdirectives'} .= $directiveLine . "\n";
	}
    }		
}

#==============================================================================
# uses TaskMaker.pm to get the appropriate pe layout values for the run.  
# Set the value as instance variables in the object.  
# This can also be called from overrideNodeCount, in which case values can be
# manually overridden. 
#==============================================================================
sub setTaskInfo()
{
    my $self = shift;
    chdir $self->{'caseroot'};
    my $taskmaker = new Task::TaskMaker(cimeroot => $self->{'cimeroot'});
    $self->{'taskmaker'} = $taskmaker;
    $self->{'sumpes'} = $taskmaker->sumPES();
    $self->{'tasks_per_node'} = $taskmaker->taskPerNode();
    $self->{'MAX_TASKS_PER_NODE'} = $taskmaker->maxTasksPerNode();
    $self->{'tasks_per_numa'} = $taskmaker->taskPerNuma();
    $self->{'fullsum'} = $taskmaker->sumOnly();
    $self->{'task_count'} = $taskmaker->sumOnly();
    $self->{'sumtasks'} = $taskmaker->sumTasks();
    $self->{'num_tasks'} = $taskmaker->sumTasks();
    $self->{'totaltasks'} = $taskmaker->sumTasks();
    $self->{'maxthreads'} = $taskmaker->maxThreads();
    $self->{'taskgeometry'} = $taskmaker->taskGeometry();
    $self->{'threadgeometry'} = $taskmaker->threadGeometry();
    $self->{'taskcount'} = $taskmaker->taskCount();
    $self->{'num_nodes'} = $taskmaker->nodeCount();
    $self->{'thread_count'} = $taskmaker->threadCount();
    $self->{'pedocumentation'} = $taskmaker->document();
    $self->{'ptile'}       = $taskmaker->ptile();
    chdir $self->{'cwd'};
    if(defined $self->{'overridenodecount'})
    {
	$self->{'sumpes'} = $self->{'overridenodecount'};
	$self->{'totaltasks'} = $self->{'overridenodecount'};
	$self->{'fullsum'} = $self->{'overridenodecount'};
	$self->{'sumtasks'} = $self->{'overridenodecount'};
	$self->{'task_count'} = $self->{'overridenodecount'};
	$self->{'num_nodes'} = $self->{'overridenodecount'};
	$self->{'tasks_per_node'} = $taskmaker->taskPerNode();
	$self->{'pedocumentation'} = "";
    }
}


sub set
{
    my ($self, $hash) = @_;

    foreach (keys %$hash){
	$self->{$_} = $hash->{$_};
    }

}



#==============================================================================
# setwalltime must be called before setqueue, we need the chosen walltime before setting the queue. 
#==============================================================================
sub setWallTime()
{
    my $self = shift;
    # Get the wallclock time from env_batch.xml if its defined there
    # otherwise get the default from config_machines.xml
    # and set it in env_batch.xml
    my $walltime = $self->{envBatch}{$self->{job}}{JOB_WALLCLOCK_TIME};
    if(defined $walltime and (! $walltime =~ /^\s*$/)){
	$self->{wall_time} = $walltime;
	return;
    }


    $self->getBatchConfigParser();
    $self->getConfigMachinesParser();
    $self->getEstCost();
    my $batchparser = $self->{'batchparser'};
    my $configmachinesparser = $self->{'configmachinesparser'};
    
    # loop through the walltime values, and set the walltime based on the reported EST_COST of the run. 
    my @walltimes = $configmachinesparser->findnodes("/config_machines/machine[\@MACH=\'$self->{'machine'}\']/batch_system/walltimes/walltime");

    # go through the walltime elements, and if our estimated cost is greater than the element's estimated cost, 
    # then set the walltime. 
    foreach my $welem(@walltimes)
    {
	next if ! defined $welem->getAttribute('ccsm_estcost');
	my $testcost = $welem->getAttribute('ccsm_estcost');
	if($self->{'CCSM_ESTCOST'} > $testcost)
	{
	    $self->{'wall_time'} = $welem->textContent();
	}
    }
    # if we didn't find a walltime previously, use the default. 
    if (! defined $self->{'wall_time'})
    {
	my @defwtimeelems = $configmachinesparser->findnodes("/config_machines/machine[\@MACH=\'$self->{'machine'}\']/batch_system/walltimes/walltime[\@default=\'true\']");
	if(@defwtimeelems)
	{
	    my $defaultelem = $defwtimeelems[0];
	    $self->{'wall_time'} = $defaultelem->textContent();
	}
    }
    if(defined $self->{walltimemax}){
	my @wtmax = split(':',$self->{walltimemax});
	my @wt = split(':',$self->{wall_time});

	for(my $i=0;$i<$#wtmax;$i++){
	    if($wtmax[$i]<$wt[$i]){
		$self->{wall_time} = $self->{walltimemax};
		last;
	    }
	    last if($wtmax[$i] > $wt[$i]);
	}
    }
    $self->{envBatch}->set("JOB_WALLCLOCK_TIME",$self->{job},$self->{wall_time});
}

#==============================================================================
# use the ProjectTools module to set both the account and project.  
#==============================================================================
sub setProject()
{
    my $self = shift;
    
    if(defined $self->{job}){
	if($self->{envBatch}{$self->{job}}{PROJECT_REQUIRED} eq "TRUE"){
	    $self->{project} = $self->{envBatch}{$self->{job}}{PROJECT};
	}
    }

}

#==============================================================================
# Get the estimated cost for this run.  This value is currently calculated as part of case_setup. 
# TODO: modularize the cost calculation??? 
#==============================================================================
sub getEstCost()
{
    my $self = shift;
    chdir $self->{'caseroot'};
    $self->{'CCSM_ESTCOST'} = `./xmlquery CCSM_ESTCOST -value`;
    chdir $self->{'cwd'};
}

#==============================================================================
# set the run queue for the selected machine, based on the walltime and the node count. 
#==============================================================================
sub setQueue()
{
    my $self = shift;
    
    # Get the queue from env_batch.xml if its defined there
    # otherwise get the default from config_machines.xml
    # and set it in env_batch.xml
    if(! defined $self->{envBatch}){
	$logger->logdie("envBatch not defined");
    }elsif(! defined $self->{job}){
	$logger->logdie("job not defined");
    }

    my $queue = $self->{envBatch}{$self->{job}}{JOB_QUEUE};
    
    

    if(defined $queue && ! ($queue =~ /^\s*$/ )){
	$self->{queue} = $queue;
	$logger->debug("Using queue $self->{queue} from env_batch.xml for $self->{job}");
	return;
    }


    $logger->debug("setQueue 1");
    #get the batch config parser, and the estimated cost of the run. 
    $self->getBatchConfigParser();	
    $logger->debug("setQueue 2");

    $self->getConfigMachinesParser();
    $logger->debug("setQueue 3");
    $self->getEstCost();
    my $batchparser = $self->{'batchparser'};
    my $configmachinesparser = $self->{'configmachinesparser'};

    $logger->debug("calling parser");

    # First, set the queue based on the default queue defined in config_batch.xml. 
    my @defaultqueue = $configmachinesparser->findnodes("/config_machines/machine[\@MACH=\'$self->{'machine'}\']/batch_system/queues/queue[\@default=\'true\']");

    $logger->debug("setting queue");
    
    # set the default queue IF we have a default queue defined, some machines (blues) do not allow one to 
    # specifiy the queue directly. 
    if(@defaultqueue)
    {
        my $defelement = $defaultqueue[0];
        $self->{'queue'} = $defelement->textContent();
    }

    # We may have a default queue at this point, but if there is a queue that our job's node count
    # falls in between, then we should use that queue. 
    my @qelems = $configmachinesparser->findnodes("/config_machines/machine[\@MACH=\'$self->{'machine'}\']/batch_system/queues/queue");
    foreach my $qelem(@qelems)
    {
	# get the minimum/maximum # nodes allowed for each queue.  
	my $jobmin = undef;
	my $jobmax = undef;
	$jobmin = $qelem->getAttribute('jobmin');
	$jobmax = $qelem->getAttribute('jobmax');
	$self->{walltimemax} = $qelem->getAttribute('walltimemax');
	# if the fullsum is between the min and max # jobs, then use this queue.  
	if(defined $jobmin && defined $jobmax && $self->{'fullsum'} >= $jobmin && $self->{'fullsum'} <= $jobmax)
	{
	    $self->{'queue'} = $qelem->textContent();
	}
    }
    if(defined $self->{queue}){  
      $self->{envBatch}->set("JOB_QUEUE",$self->{job},$self->{queue});
      $logger->debug("Using queue $self->{queue} ");
    }

}

#==============================================================================
# set the cesm run command per machine.  
#==============================================================================
sub setCESMRun()
{
    my $self = shift;
    my $batchparser = $self->{'batchparser'};
    my $configmachinesparser = $self->{'configmachinesparser'};
    
    # get the default run suffix, this should be the same for all machines. 
    my @suffixes = $configmachinesparser->findnodes("/config_machines/default_run_suffix");
    if(! @suffixes)
    {
	die "no default run suffix defined!";
    }
    
    my $defaultrunsuffix = $suffixes[0]->textContent();
    # get the batch system type for this machine.  
    my @batchtype = $configmachinesparser->findnodes("/config_machines/machine[\@MACH=\'$self->{'machine'}\']/batch_system");

    if(! @batchtype)
    {
	my $msg = "No batch system type configured for this machine!  Please see config_batch.xml\n";
	$msg .=   "within CESM's Machines directory, and add a batch system type for this machine\n";
	die $msg;
    }

    $self->{'batchsystem'} = $batchtype[0]->getAttribute('type');
    my $config = $self->{'config'};
    
    # First, get all the mpirun elements.  
    my @mpielems = $configmachinesparser->findnodes("/config_machines/machine[\@MACH=\'$self->{'machine'}\']/mpirun");
    my $chosenmpielem = undef;
    
    # Iterate through all the mpi elements. 
    foreach my $mpielem(@mpielems)
    {
	# if any of the attributes match any of our instance variables, 
	# we have a match, break out of the attribute loop, and use that as our 
	# chosen mpi run element. 
	if(! $mpielem->hasAttributes())
	{
	    $chosenmpielem = $mpielem;
	}
	else
	{
	    my $attrMatch = 1;
	    
	    my @mpiattrs = $mpielem->getAttributes();
	    foreach my $attr(@mpiattrs)
	    {
		my $attrName = $attr->getName();
		my $attrValue = $attr->getValue();
		if(defined $self->{$attrName} && (lc $self->{$attrName} ne $attrValue))
		{
		    $attrMatch = 0;
		    last;
		}
	    }
	    if($attrMatch)
	    {
		$chosenmpielem = $mpielem;
	    }
	}
    }
    
    # if we don't have an mpirun command, find the default. 
    if(! defined $chosenmpielem)
    {
	my @defaultmpielems = $configmachinesparser->findnodes("/config_machines/machine[\@MACH=\'$self->{'machine'}\']/mpirun[\@mpilib=\'default\']");
	foreach my $defelem(@defaultmpielems)
	{
	    if(! $defelem->hasAttributes() )
	    {
		$chosenmpielem = $defelem;
	    }	
	    else
	    {
		my $attrMatch = 1;
		my @attrs = $defelem->getAttributes();
		foreach my $attr(@attrs)
		{
		    my $attrName = $attr->getName();
		    my $attrValue = $attr->getValue();
		    next if($attrValue eq 'default');
		    my $lcAttrName = lc $attrName;
		    if(defined $self->{$lcAttrName} && (lc $self->{$attrName} ne lc $attrValue))
		    {
			$attrMatch = 0;
			last;	
		    }
		}
		if($attrMatch)
		{
		    $chosenmpielem = $defelem;
		    last;
		}
		
	    }
	}
	#$chosenmpielem = $defaultmpielems[0];
    }
    
    # die if we haven't found an mpirun for this machine by now..
    if(! defined $chosenmpielem)
    {
	die "no mpirun could be found for this machine!";
    }
    
    my $mpiargstring = '';
    my $executableString = undef;
    my @exeelems = $chosenmpielem->findnodes("./executable");

    # Iterate through the executable elements, get the mpirun, etc 
    # arguments. 
    foreach my $exeelem(@exeelems)
    {
	$executableString = $exeelem->textContent();
        
	my @arguments = $chosenmpielem->findnodes("./arguments/arg");
	
	# Iterate through the arg elements..
	foreach my $arg(@arguments)
	{
	    my $tmpArg = undef;
	    
	    
	    my $argName = $arg->getAttribute('name');
	    my $argValue = $arg->textContent();
	    
	    # If the arg value is wrapped in double underscores, we
	    # we need to replace the double underscore with either 
	    # actual value if defined, the default value if defined and no
	    # instance variable exists, or discard the argument completely 
	    # if neither are defined. 
	    while($argValue =~ /({{ \w+ }})/)
	    {
		# get the matched string, and get the
		# string we need to replace without the underscores. 
		my $matchedString = $1;
		my $stringToReplace = $matchedString;
		$stringToReplace =~ s/{{ //g;
		$stringToReplace =~ s/ }}//g;

		# the actual argument is stored here, 
		# this way we can transform the thing as we
		# need to 
		
		# if we don't have an instance variable, and we do have a default value, 
		# use the default value for the double underscore substitution. 
		if(! defined $self->{$stringToReplace} && $arg->hasAttribute('default'))
		{
		    my $defaultAttr = $arg->getAttribute('default');
		    $argValue =~ s/$matchedString/$defaultAttr/g;
		    
		}
		elsif( defined $self->{$stringToReplace} && ! $arg->hasAttribute('default'))
		{
		    my $instanceVar = $self->{$stringToReplace};
		    $argValue =~ s/$matchedString/$instanceVar/g;
		    #print "matched string: $matchedString\n";
		    #print "actual argument is now: $argValue\n";
		}
		elsif(! defined $self->{$stringToReplace} && ! $arg->hasAttribute('default'))
		{	
		    $argValue = '';
		}
	    }
	    $mpiargstring .= $argValue . ' ' ;
	}
    }
    
    $self->{'mpirun'} .= "qx( " . $executableString . " " . $mpiargstring .  " " . $defaultrunsuffix . ");";
}


#==============================================================================
# substitute all the template strings with the actual values, and write the new
# run script into the case root. 
#==============================================================================
sub writeBatchScript()
{
    my $self = shift;
    my $inputfilename = shift;
    my $outputfilename = shift;
    my $batchtemplate = '';
    open (my $RUNTMPL, "<", $inputfilename) or die "could not open run template $inputfilename, $!";
    my $templatetext = join("", <$RUNTMPL>);
    close $RUNTMPL;
    
    # transform the template variables to their actual values. 
    
    $templatetext = $self->transformVars($templatetext);
    
    # write the new run script. 
    open (my $RUNSCRIPT, ">", $outputfilename) or die "could not open new script, $!";
    print $RUNSCRIPT $templatetext;
    close $RUNSCRIPT;
    chmod 0755, $outputfilename;
}

#==============================================================================
# Get the long-term archiver options from $CIMEROOT/cime_config/cesm/machines 
# These options will be used when creating the lt_archive run scrip
#==============================================================================
sub getLtArchiveOptions()
{
    my $self = shift;
    
    my $lt_archive_file = $self->{machroot} . "/config_lt_archive.xml";
    my $ltarchxml = XML::LibXML->new(no_blanks => 1);
    my $ltarchparser = $ltarchxml->parse_file($lt_archive_file) or die "could not parse $lt_archive_file, $! $?";
    my $ltarchroot = $ltarchparser->getDocumentElement();
    
    my $lt_archive_args;
    my @argnodes;
    
    @argnodes = $ltarchroot->findnodes("//machine[\@name=\'$self->{machine}\']/lt_archive_args");
    
    # First, search for the machine-specific lt_archive_args
    if(! @argnodes)
    {
        @argnodes = $ltarchroot->findnodes("//machine[\@name=\'default\']/lt_archive_args");
    }
    
    # if no default is found, then set lt_archive_args to empty
    if(! @argnodes)
    {
        $lt_archive_args = '';
    }
    else
    {
        my $argnode = $argnodes[0];
        $self->{lt_archive_args} = $argnode->textContent();
    }
}

#==============================================================================
# Lets us manually set a node count so that we can override what TaskMaker is giving us
# for batch scripts like the st archiver, lt archiver, etc..
#==============================================================================
sub overrideNodeCount()
{
    my $self = shift;
    my $nodeCount = shift;
    $self->{'overridenodecount'} = $nodeCount;
}

#==============================================================================
# Simple factory class to get the right BatchMaker class for each machine.  
# The only downside to this strategy is that we have to have a BatchMaker_${machine} 
# class for every machine we port. 
# TODO: REFACTOR this so that if no machine or batch class is found, then the base
# class is returned. 
#==============================================================================
package Batch::BatchFactory;
use Data::Dumper;
sub getBatchMaker()
{
    my (%params) = @_;

    if(! defined $params{'machine'})
    {
	die "BatchFactory: params{'machine'} must be defined!";
    }
    
    
    my $machine = $params{'machine'};
    my $batchmaker = Batch::BatchMaker->new(%params);
    my $subclassname = "Batch::BatchMaker_" . $machine;
    if($params{'machine'} =~ /pleiades/)
    {
	my $newmachname = $params{'machine'};
	$newmachname =~ s/-/_/g;
	$subclassname = "Batch::BatchMaker_" . $newmachname;
    }

    # Try to call the _test method on the class. 
    # If we get an error, it means the class doesn't
    # exist, and we need to return an instance of the base
    # class. 
    my $rv = eval
    {
	bless $batchmaker, $subclassname;
	$batchmaker->_test();
	1;
    };

    if(! $@)
    {
	return $batchmaker;
    }
    else
    {
	bless $batchmaker, "Batch::BatchMaker";
	return $batchmaker;	
    }
}
#==============================================================================
#==============================================================================
package Batch::BatchMaker_lsf;
use base qw (Batch::BatchMaker);
sub _test()
{
    my $self = shift;
    return 1;
}

#==============================================================================
#==============================================================================
package Batch::BatchMaker_pbs;
use base qw (Batch::BatchMaker);
sub _test()
{
    my $self = shift;
    return 1;
}

#==============================================================================
#==============================================================================
package Batch::BatchMaker_slurm;
use base qw (Batch::BatchMaker);
sub _test()
{
    my $self = shift;
    return 1;
}

#==============================================================================
#==============================================================================
package Batch::BatchMaker_cray;
use base qw(Batch::BatchMaker);
use Data::Dumper;
use POSIX;

sub _test()
{
    my $self = shift;
    return 1;
}
sub setTaskInfo()
{
    my $self = shift;
    #print "in Batch::BatchMaker_cray setTaskInfo\n";
    #my $taskmaker = new Task::TaskMaker(cimeroot => $self->{'cimeroot'});
    #my $config = $taskmaker->{'config'};
    #my $maxTasksPerNode = ${$taskmaker->{'config'}}{'MAX_TASKS_PER_NODE'};
    #$self->{'mppsize'} = $self->{'mppsum'};


    #if($self->{'mppsize'} % $maxTasksPerNode > 0)
    #{
    #    my $mppnodes = POSIX::floor($self->{'mppsize'} / $maxTasksPerNode);
    #    $mppnodes += 1;
    #    $self->{'mppsize'} = $mppnodes * $maxTasksPerNode;
    #}
    #$self->{'mppwidth'} = $self->{'mppsize'};

    $self->SUPER::setTaskInfo();
}

#==============================================================================
#==============================================================================
package Batch::BatchMaker_edison;
use base qw (Batch::BatchMaker_cray);
sub _test()
{
    my $self = shift;
    return 1;
}
sub setTaskInfo()
{
    my $self = shift;
    $self->SUPER::setTaskInfo();
    my $taskmaker = new Task::TaskMaker(caseroot => $self->{'caseroot'},
	                                cimeroot => $self->{cimeroot});

    my $maxTasksPerNode = ${$taskmaker->{'config'}}{'MAX_TASKS_PER_NODE'};
    my $pes_per_node = ${$taskmaker->{'config'}}{'PES_PER_NODE'};

    # Handle the case where

    $self->{'mppsize'}  = $taskmaker->sumTasks();

    if($self->{mppsize} > $pes_per_node && $self->{'mppsize'} % $pes_per_node > 0)
    {
	print "mppsize = $self->{mppsize} pes_per_node=$pes_per_node \n";
	die("odd number of tasks to handle");
#        my $mppnodes = POSIX::floor($self->{'mppsize'} / $maxTasksPerNode);
#        $mppnodes += 1;
#        $self->{'mppsize'} = $mppnodes * $maxTasksPerNode;
    }

    $self->{'mppsum'} = $taskmaker->sumPES();
    
    if($self->{maxthreads} == 1){
	$self->{mppwidth} = $self->{mppsum};
    }else{
	$self->{mppwidth} = $self->{mppsum} * $pes_per_node/ $maxTasksPerNode;
    }

    if($self->{mppwidth} < $pes_per_node){
	$self->{mppwidth} = $pes_per_node;
    }
    
    if(defined $self->{'overridenodecount'})
    {
        $self->{mppwidth} = 24;
        $self->{num_tasks} = 1;
        $self->{tasks_per_numa} = 1;
        $self->{tasks_per_node} = 1;
    }

}

sub setCESMRun()
{
    my $self = shift;
    
    # For the aprun command we only want -S tasks_per_numa
    # and -cc numa_node to be set if the tasks per node is > 1
    if($self->{'tasks_per_node'} > 1)
    {
	$self->{'numa_node'} = 'numa_node';
    }
    else
    {
	$self->{'tasks_per_numa'} = undef;
	$self->{'numa_node'} = undef;
    }
    $self->SUPER::setCESMRun();


}


#==============================================================================
#==============================================================================
package Batch::BatchMaker_hopper;
use base qw (Batch::BatchMaker_cray);
use Data::Dumper;
use POSIX;
sub _test()
{
    my $self = shift;
    return 1;
}
sub setTaskInfo()
{
    my $self = shift;
    my $taskmaker = new Task::TaskMaker(cimeroot => $self->{'cimeroot'});
    $self->{'mppsum'} = $taskmaker->sumOnly();
    $self->SUPER::setTaskInfo();
}


#==============================================================================
#==============================================================================
package Batch::BatchMaker_mira;
use base qw (Batch::BatchMaker );
use Data::Dumper;
sub _test()
{
    my $self = shift;
    return 1;
}
# Mira does not need batch directives..
sub transformVars()
{
    my $self = shift;
    my $text = shift;
    $text =~ s/{{ batchdirectives }}//g;
    $text = $self->SUPER::transformVars($text);
}

sub setBatchDirectives()
{
    my $self = shift;
    $self->{'batchdirectives'} = undef;
}

sub setCESMRun()
{
    my $self = shift;
    $self->{'mpirun'} = '';
    $self->SUPER::setCESMRun();
    my $mpirun = $self->{'mpirun'};

    my $code1 =<<'E1';
    my $LOCARGS = "--block $ENV{'COBALT_PARTNAME'}";
    if(defined $ENV{'COBALT_CORNER'})
    {
        $LOCARGS .= "--corner $ENV{'COBALT_CORNER'}";
    }
    if(defined $ENV{'COBALT_SHAPE'})
    {
        $LOCARGS .= "--shape $ENV{'COBALT_CORNER'}";
    }
    if(defined $ENV{'LOCAL_ARGS'})
    {
        $LOCARGS .= " $ENV{LOCAL_ARGS} ";
    }
E1
	my $code2=<<"E2";
    $mpirun
E2
	my $code = "$code1\n$code2\n";
    $self->{'mpirun'} = "$code\n";
    
}


package Batch::BatchMaker_gaea;
use base qw (Batch::BatchMaker );
sub _test()
{
    my $self = shift;
    return 1;
}

sub setTaskInfo()
{
    my $self = shift;
    my $taskmaker = new Task::TaskMaker(cimeroot => $self->{'cimeroot'});
    my $mppsize = $taskmaker->sumOnly();
    my $config = $taskmaker->{'config'};
    my $maxTasksPerNode = ${$taskmaker->{'config'}}{'MAX_TASKS_PER_NODE'};

    if($mppsize % $maxTasksPerNode > 0)
    {
	my $mppnodes = $mppsize / $maxTasksPerNode;
	$mppnodes = $mppnodes + 1;
	$mppsize = $mppnodes * $maxTasksPerNode;
    }
    $self->{'mppsize'} = $mppsize;
    $self->SUPER::setTaskInfo();
}

sub setQueue()
{
    my $self = shift;
    if($self->{'mppsize'} > 860)
    {
	$self->{'queue'} = "batch";
	$self->{'partition'} = "c2";
    }
    else
    {
	$self->{'queue'} = "debug";
	$self->{'partition'} = "c1";
    }
}
package Batch::BatchMaker_erebus;
use base qw (Batch::BatchMaker );
sub _test()
{
    my $self = shift;
    return 1;
}

sub writeBatchScript()
{
    my $self = shift;
    if($ENV{'HOSTNAME'} =~ /login/)
    {
        my $hostfilename = $self->{caseroot} . "/hostfile";
        open my $HFILE, "<", $hostfilename or die "could not open $hostfilename for writing!";
        print $HFILE $ENV{'HOSTNAME'}; 
        close $HFILE;
        $ENV{'MP_HOSTFILE'} = $hostfilename;
        $ENV{'MP_PROCS'} = 1;
        
    }
    $self->SUPER::writeBatchScript();
}


1;
