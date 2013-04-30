package PowerdnsTango::Views;
use Dancer ':syntax';

use Dancer::Plugin::Database;
use Dancer::Plugin::FlashMessage;
use Dancer::Plugin::Res;
use Dancer::Session::Storable;
use Dancer::Template::TemplateToolkit;
use Dancer::Plugin::Ajax;
use Dancer::Exception qw(:all);

use DateTime;
use Data::Page;
use Data::Validate::IP qw(is_ipv4 is_ipv6);
use Scalar::Util qw(looks_like_number);
use PowerdnsTango::Acl qw(user_acl is_admin user_id);
use PowerdnsTango::Views::Config;

our $VERSION = '0.3';

prefix '/views';

get '/' => sub {
	my @views = _get_view(':ALL');

	return res 200 => { result => \@views }
		if request->is_ajax;
	return template('views-list', { views => \@views } );
};

post '/add' => sub {
	unless (is_admin) {
		return res 403
			if request->is_ajax;
		flash error => "Permission denied";
		return redirect '/views';
	}

	my $view = {
		name => params->{view_name},
		clients => params->{view_clients} || '',
		destinations => params->{view_destinations} || '',
		recursive_only => params->{view_recursive_only} || 0,
	};

	try {
		my $view_id = _create_view($view);
		
		return res 200 => { message => "View created", id => $view_id }
			if request->is_ajax;
		flash message => "View created";
		return redirect '/views/'.$view_id;
	}
	catch {
		my ($e) = @_;
		if ($e->does('InvelidArgument')) {
			return res 400 => { message => $e->message }
				if request->is_ajax;
			flash error => $e->message;
			return redirect '/views';
		}
		else {
			$e->rethrow;
		}
	}
};

post '/:id/update' => sub {
	unless (is_admin) {
		return res 403
			if request->is_ajax;
		flash error => "Permission denied";
		return redirect '/views';
	}

	my $view_id = params->{id} || 0;

	my $view = {
		name => params->{view_name},
		clients => params->{view_clients} || '',
		destinations => params->{view_destinations} || '',
		recursive_only => params->{view_recursive_only} || 'NO',
	};

	try {
		my $view_id = _update_view($view_id, $view);
		
		return res 200 => { message => "View updated", id => $view_id, %{$view} }
			if request->is_ajax;
		flash message => "View updated";
		return redirect '/views/'.$view_id;
	}
	catch {
		my ($e) = @_;
		if ($e->does('InvelidArgument')) {
			return res 400 => { message => $e->message }
				if request->is_ajax;
			flash error => $e->message;
			return redirect '/views';
		}
		if ($e->does('InvelidArgument')) {
			return res 400 => { message => $e->message }
				if request->is_ajax;
			flash error => $e->message;
			return redirect '/views';
		}
		else {
			$e->rethrow;
		}
	}
};

get '/:id' => sub {
	my $id = params->{id} || 0;

	my $view = database->quick_select('pt_views', {id => $id});
	
	unless ($view) {
		return res 404 => { message => 'View not found' }
			if request->is_ajax;

		flash error => 'View not found';
		return redirect '/views';
	}

	my @config = database->quick_select('pt_views_config', {view_id => $id});

	return template 'views-info', {
		v => $view,
		config => \@config,
		can_edit => is_admin,
	};
};

# "MODEL"
sub _get_view {
	my ($view_id) = @_;

	if (not defined $view_id or $view_id eq ':ALL') {
		return (database->quick_select('pt_views', {}, {order_by => 'name'}));
	}
	elsif (looks_like_number($view_id)) {
		return database->quick_select('pt_views', {id => $view_id});
	}
	else {
		raise 'InvalidArgument' => "Expected integer view_id";
	}
}

sub _exists_view {
	my ($view_id) = @_;

	raise 'InvalidArgument' => "Expected integer view_id"
		unless (looks_like_number($view_id));

	return database->quick_lookup('pt_views', {id => $view_id}, 'id');
}

sub _create_view {
	my ($view) = @_;

	for my $exp (qw(clients destinations recursive_only name)) {
		raise 'InvalidArgument' => "Missing value for $exp"
			unless defined $view->{$exp};
	}
	
	raise 'InvalidArgument' => "Invalid view name"
		unless ($view->{name} =~ /^[a-z0-9][a-z0-9-]*[a-z0-9]$/i);

	database->quick_insert('pt_views', {
		name => $view->{name}, 
		clients => $view->{clients}, 
		destinations => $view->{destinations}, 
		recursive_only => $view->{recursive_only}
	});

	return database->last_insert_id(undef, undef, 'pt_views', 'id');
}

sub _update_view {
	my ($view_id, $view) = @_;

	for my $exp (qw(clients destinations recursive_only name)) {
		raise 'InvalidArgument' => "Missing value for $exp"
			unless defined $view->{$exp};
	}

	raise 'InvalidArgument' => "Expected integer view_id"
		unless (looks_like_number($view_id));
		
	raise 'InvalidArgument' => "Invalid recursive_only value (YES/NO)"
		unless ($view->{recursive_only} =~ /^(YES|NO)$/i);

	my $old_view = database->quick_select('pt_views', { id => $view_id });

	raise 'ObjectNotFound' => 'View not found'
		unless $old_view;

	if ($old_view->{name} ne $view->{name}) {
		raise 'ObjectAlreadyExists' => 'View with that name already exists. Name must be unique.'
			if database->quick_lookup('pt_views', { name => $view->{name} }, 'id');

		raise 'InvalidArgument' => "Invalid view name"
			unless ($view->{name} =~ /^[a-z0-9][a-z0-9-]*[a-z0-9]$/i);
	}

	database->quick_update('pt_views', { id => $view_id }, {
		name => $view->{name}, 
		clients => $view->{clients}, 
		destinations => $view->{destinations}, 
		recursive_only => $view->{recursive_only}
	});

	return $view_id;
}

prefix undef;

1;
