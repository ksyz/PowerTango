package Dancer::Plugin::Journal;

use strict;
use Dancer ':syntax';
use Dancer::Plugin;
use Dancer::Plugin::Database;
use Dancer::Session::Storable;
use Scalar::Util 'blessed';

my $dancer_version = (exists &dancer_version) ? int(dancer_version()) : 1;
my $logger;

if ($dancer_version == 1) {
    require Dancer::Config;
    Dancer::Config->import();

    $logger = sub { Dancer::Logger->can($_[0])->($_[1]) };
} else {
    $logger = sub { log @_ };
}


our $VERSION = '1.0';

my $settings = undef;

sub _load_settings {
    $settings = plugin_setting();
}

my %T = (
	domains => 1,
#	domains_acl_tango => 1,
	records => 1,
	tempaltes_tango => 1,
#	template_acl_tango => 1,
	template_records_tango => 1,
	admin_settings => 1,
	users_tango => 1,
);

# object/o
# source/package
# intent/i
# old_data/old
# new_data/new
# oid/id
# message/m
register 'journal' => \&_journal;

sub _journal {
	my ($self, %args) = plugin_args(@_);
	my ($package, $filename, $line) = caller;

	die ('Missing journal intent') unless $args{i};
	die ('Invalid journal intent' . $args{i}) unless grep {$args{i} eq $_} qw(READ UPDATE DELETE CREATE LOG);
	die ('Missing journal object') unless $args{o};
	
	return 
		unless exists($T{$args{o}});

	my $old = '';
	if ($args{old} || $args{id} || $args{where}) {
		if ($args{id}) {
			$old = database->quick_select($args{o}, {id => $args{id}});
		}
		elsif ($args{where}) {
			$old = database->quick_select($args{o}, $args{where});
		}
		else {
			$old = $args{old};
		}

		unless ($old) {
			Dancer::Logger::warning("Didn't got old data for journal puproses");
			return;
		}
		else {
			$old = to_json($old);
		}
	}

	my $new = '';
	if (defined $args{new}) {
		$new = to_json($args{new});
	}

	return database->quick_insert('!journal_tango', {
		author => session('user_login') || '',
		address => request->remote_address,
		object => $args{o},
		source => $package,
		intent => $args{i},
		old_data => $old,
		new_data => $new,
		message => (defined $args{m} ? $args{m} : ''),
	});
};

hook 'before_db_update' => sub {
	my ($args) = @_;
    my ($caller, $type, $table_name, $data, $where) = @{$args->{args}};

	return undef
		unless exists $T{$table_name};

	return _journal(i => 'UPDATE', o => $table_name, new => $data, where => $where);
};

hook 'before_db_insert' => sub {
	my ($args) = @_;
    my ($caller, $type, $table_name, $data, $where) = @{$args->{args}};

	return undef
		unless exists $T{$table_name};

	return _journal(i => 'CREATE', o => $table_name, new => $data);
};

hook 'before_db_delete' => sub {
	my ($args) = @_;
    my ($caller, $type, $table_name, $data, $where) = @{$args->{args}};

	return undef
		unless exists $T{$table_name};

	return _journal(i => 'DELETE', o => $table_name, where => $where);
};

register_plugin;
1;
