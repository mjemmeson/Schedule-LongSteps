package Schedule::LongSteps;

# ABSTRACT: Manage long term processes over arbitrary large spans of time.

use Moose;

=head1 NAME

Schedule::LongSteps - Manage long term processes over arbitrary large spans of time.

=head1 ABSTRACT

This attempts to solve the problem of defining and running a set of potentially conditional steps accross an arbitrary long timespan.

An example of such a process would be: "After an order has been started, if more than one hour, send an email reminder every 2 days until the order is finished. Give up after a month"". You get the idea.

Such a process is usually a pain to implement and this is an attempt to provide a framework so it would make writing and testing such a process as easy as writing and testing a good old Class.

=head1 CONCEPTS

=head2 Process

A Process represents a set of logically linked steps that need to run over a long span of times (hours, months, even years..). It persists in a Storage.

At the logical level, the persistant Process has the following attributes (See L<Schedule::LongSteps::Storage::DBIxClass> for a comprehensive list):

- what. Which step should it run next.

- run_at. A L<DateTime> at which this next step should be run. This allows running a step far in the future.

- status. Is the step running, or paused or is the process terminated.

- state. The persistant state of your application. This should be a pure Perl hash (JSONable).

Users (you) implement their business process as a subclass of L<Schedule::LongSteps::Process>. Such subclasses can have contextual properties
as Moose properties that will have to be supplied by the L<Schedule::LongSteps> management methods.

=head2 Steps

A step is simply a subroutine in a process class that runs some business code. It always returns either a new step to be run
or a final step marker.

=head2 Storage

A storage provides the backend to persist processes. Build a Schedule::LongSteps with a storage instance.

See section PERSISTANCE for a list of available storage classes.

=head2 Manager: Schedule::LongSteps

A L<Schedule::LongSteps> provides an entry point to all thing related to Schedule::LongSteps process management.
You should keep once instance of this in your application (well, one instance per process) as this is what you
are going to use to launch and manage processes.

=head1 QUICK START AND SYNOPSIS

First write a class to represent your long running set of steps

  package My::Application::MyLongProcess;

  use Moose;
  extends qw/Schedule::LongSteps::Process/;

  # Some contextual things.
  has 'thing' => ( is => 'ro', required => 1); # Some mandatory context provided by your application at each regular run.

  # The first step should be executed after the process is installed on the target.
  sub build_first_step{
    my ($self) = @_;
    return $self->new_step({ what => 'do_stuff1', run_at => DateTime->now() });
  }

  sub do_stuff1{
     my ($self) = @_;

      # The starting state
      my $state = $self->state();

      my $thing = $self->thing();

     .. Do some stuff and return the next step to execute ..

      return $self->new_step({ what => 'do_stuff2', run_at => DateTime->... , state => { some => 'jsonable', hash => 'ref'  ]  });
  }

  sub do_stuff2{
      my ($self, $step) = @_;

      $self->wait_for_steps('do_stuff1', 'do_stuff2' );

      .. Do some stuff and terminate the process or goto do_stuff1 ..

       if( ... ){
           return Schedule::LongSteps::Step->new({ what => 'do_stuff1', run_at => DateTime->... , state => { some jsonable structure } });
       }
       return $self->final_step({ state => { the => final, state => 1 }  }) ;
  }

  __PACKAGE__->meta->make_immutable();

Then in you main application do this once per 'target':

   my $dbic_storage = Schedule::LongSteps::Storage::DBIxClass->new(...);
   # Keep only ONE Instance of this in your application.
   my $longsteps = Schedule::LongSteps->new({ storage => $dbic_storage });
   ...

   $longsteps->instanciate_process('My::Application::MyProcess', { thing => 'whatever' }, { the => 'init', state => 1 });

Then regularly (in a cron, or a recurring callback):

   my $dbic_storage = Schedule::LongSteps::Storage::DBIxClass->new(...);
   # Keep only ONE instance of this in your application.
   my $longsteps = Schedule::LongSteps->new({ storage => $dbic_storage });
   ...

   $long_steps->run_due_steps({ thing => 'whatever' });

=head1 EXAMPLE

Look at L<https://github.com/jeteve/Schedule-LongSteps/blob/master/t/fullblown.t> for a full blown working
example.

=head1 PERSISTANCE

The persistance of processes is managed by a subclass of L<Schedule::LongSteps::Storage> that you should instanciate
and given to the constructor of L<Schedule::LongSteps>

Example:

   my $dbic_storage = Schedule::LongSteps::Storage::DBIxClass->new(...);
   my $longsteps = Schedule::LongSteps->new({ storage => $dbic_storage });
   ...

Out of the box, the following storage classes are available:

=over

=item L<Schedule::LongSteps::Storage::Memory>

Persist processes in memory. Not very useful, except for testing. This is the storage of choice to unit test your processes.

=item L<Schedule::LongSteps::Storage::AutoDBIx>

Persist processes in a relational DB (a $dbh from L<DBI>). This is the easiest thing to use if you want to persist processes in a database, without having
to worry about creating a DBIx::Class model yourself.

=item L<Schedule::LongSteps::Storage::DBIxClass>

Persist processes in an existing L<DBIx::Class> schema. Nice if you want to have only one instance of Schema in your application and if
don't mind writing your own resultset.

=back

=head1 COOKBOOK

=head2 WRITING A NEW PROCESS

See 'QUICK START AND SYNOPSIS'

=head2 INSTANCIATING A NEW PROCESS

See 'QUICK START AND SYNOPSIS'

=head2 RUNNING PROCESS STEPS

See 'QUICK START AND SYNOPSIS

=head2 INJECTING PARAMETERS IN YOUR PROCESSES

Of course each instance of your process will most probably need to
act on different pieces of application data. The one and only way to
give 'parameters' to your processes is to specify an initial state when
you instanciate a process:

  $longsteps->instantiate_process('My::App', { app => $app } , { work => 'on' , this => 'user_id' });

=head2 INJECTING CONTEXT IN YOUR PROCESSES

Let's say you hold an instance of your application object:

  my $app = ...;

And you want to use it in your processes:

  package MyProcess;
  ...
  has 'app' => (is => 'ro', isa => 'My::App', required => 1);

You can inject your $app instance in your processes at instanciation time:

  $longsteps->instantiate_process('My::App', { app => $app });

And also when running the due steps:

  $longsteps->run_due_steps({ app => $app });

The injected context should be stable over time. Do NOT use this to inject parameters. (See INJECTING PARAMETERS).


=head2 PROCESS WRITING

This package should  be expressive enough for you to implement business processes
as complex as those given as an example on this page: L<https://en.wikipedia.org/wiki/XPDL>

Proper support for XPDL is not implemented yet, but here is a list of recipes to implement
the most common process patterns:

=head3 MOVING TO A FINAL STATE

Simply do in your step 'do_last_stuff' implementation:

   sub do_last_stuff{
      my ($self) = @_;
      # Return final_step with the final state.
      return $self->final_step({ state => { the => 'final' , state => 1 } });
   }

=head3 DO SOMETHING ELSE IN X AMOUNT OF TIME

   sub do_stuff{
        ...
        # Do the things that have to be done NOW
        ...
        # And in two days, to this
        return $self->new_step({ what => 'do_stuff_later', run_at => DateTime->now()->add( days => 2 ) ,  state => { some => 'new one' }});
   }


=head3 DO SOMETHING CONDITIONALLY

   sub do_choose{
      if( ... ){
         return $self->new_step({ what => 'do_choice1', run_at => DateTime->now() });
      }
      return $self->new_step({ what => 'do_choice2', run_at => DateTime->now() });
   }

   sub do_choice1{...}
   sub do_choice2{...}

=head3 FORKING AND WAITING FOR PROCESSES


  sub do_fork{
     ...
     my $p1 = $self->longsteps->instanciate_process('AnotherProcessClass', \%build_args , \%initial_state );
     my $p2 = $self->longsteps->instanciate_process('YetAnotherProcessClass', \%build_args2 , \%initial_state2 );
     ...
     return $self->new_step({ what => 'do_join', run_at => DateTime->now() , { processes => [ $p1->id(), p2->id() ] } });
  }

  sub do_join{
     return $self->wait_processes( $self->state()->{processes}, sub{
          my ( @terminated_processes ) = @_;
          my $state1 = $terminated_processes[0]->state();
          my $state2 = $terminated_processes[1]->state();
          ...
          # And as usual:
          return $self->...
     });
  }

=head1 METHODS

=head2 uuid

Returns a L<Data::UUID> from the storage.

=head2 run_due_processes

Runs all the due processes steps according to now(). All processes
are given the context to be built.

Usage:

 # No context given:
 $this->run_due_processes();

 # With 'thing' as context:
 $this->run_due_processes({ thing => ... });

Returns the number of processes run

=head2 instantiate_process

Instanciate a stored process from the given process class returns a new process that will have an ID.

Usage:

  $this->instantiate_process( 'MyProcessClass', { process_attribute1 => .. } , { initial => 'state' });

=head2 find_process

Shortcut to $self->storage->find_process( $pid );

=head1 SEE ALSO

L<BPM::Engine> A business Process engine based on XPDL, in Alpha version since 2012 (at this time of writing)

=head1 Copyright and Acknowledgement

This code is released under the Perl5 Terms by Jerome Eteve (JETEVE), with the support of Broadbean Technologies Ltd.

See L<perlartistic>

=for HTML <a href="https://travis-ci.org/jeteve/Schedule-LongSteps"><img src="https://travis-ci.org/jeteve/Schedule-LongSteps.svg?branch=master"></a>

=cut

use Class::Load;
use Log::Any qw/$log/;

use Schedule::LongSteps::Storage::Memory;

has 'storage' => ( is => 'ro', isa => 'Schedule::LongSteps::Storage', lazy_build => 1);

sub _build_storage{
    my ($self) = @_;
    $log->warn("No storage specified. Will use Memory storage");
    return Schedule::LongSteps::Storage::Memory->new();
}


sub uuid{
    my ($self) = @_;
    return $self->storage()->uuid();
}

sub run_due_processes{
    my ($self, $context) = @_;
    $context ||= {};

    my $stored_processes = $self->storage->prepare_due_processes();
    my $process_count = 0;
    while( my $stored_process = $stored_processes->next() ){
        Class::Load::load_class($stored_process->process_class());
        my $process = $stored_process->process_class()->new({ longsteps => $self, stored_process => $stored_process, %{$context} });
        my $process_method = $stored_process->what();

        $process_count++;

        my $new_step_properties = eval{ $process->$process_method(); };
        if( my $err = $@ ){
            $log->error("Error running process ".$stored_process->process_class().':'.$stored_process->id().' :'.$err);
            $stored_process->update({
                status => 'terminated',
                error => $err,
                run_at => undef,
                run_id => undef,
            });
            next;
        }

        $stored_process->update({
            status => 'paused',
            run_at => undef,
            run_id => undef,
            %{$new_step_properties}
        });
    }
    return $process_count;
}

sub instantiate_process{
    my ($self, $process_class, $build_args, $init_state ) = @_;

    defined( $build_args ) or ( $build_args = {} );
    defined( $init_state ) or ( $init_state = {} );

    Class::Load::load_class($process_class);
    unless( $process_class->isa('Schedule::LongSteps::Process') ){
        confess("Class '$process_class' is not an instance of 'Schedule::LongSteps::Process'");
    }
    my $process = $process_class->new( { longsteps => $self, %{ $build_args } } );
    my $step_props = $process->build_first_step();

    my $stored_process = $self->storage->create_process({
        process_class => $process_class,
        status => 'pending',
        state => $init_state,
        %{$step_props}
    });
    return $stored_process;
}

sub find_process{
    my ($self, $pid) = @_;
    return $self->storage()->find_process($pid);
}

__PACKAGE__->meta->make_immutable();
