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

our $VERSION = '0.3';

prefix '/views';

# GET ALL
get '/:view_id/config' => sub {
	my $view_id = params->{view_id} || 0;

	try {
		my @config = _get_view_config($view_id, ':ALL') || ();

		return res 200 => { result => \@config, can_edit => is_admin }
			if request->is_ajax;
		
		return template 'views-info', {
			config => \@config,
			can_edit => is_admin,
		};
	}
	catch {
		my ($e) = @_;
		if ($e->does('InvalidArguemnt')) {
			return res 400 => { message => $e->message }
				if request->is_ajax;
			flash message => "Configuration changed";
			return redirect '/'.$view_id;
		}
		elsif ($e->does('ObjectNotFound')) {
			return res 404 => { message => $e->message }
				if request->is_ajax;
			flash message => "Configuration changed";
			return redirect '/'.$view_id;
		}
		else {
			$e->rethrow;
		}
	}
};

get '/:view_id/config/:config_id' => sub {
	my $view_id = params->{view_id} || 0;
	my $config_id = params->{view_id} || 0;

	try {
		$config_id = _exists($view_id, $config_id);
		my $config = _get_view_config($view_id, $config_id);

		return res 200 => { result => [ $config ], can_edit => is_admin }
			if request->is_ajax;
		
		return template 'views-info', {
			config => [ $config ],
			can_edit => is_admin,
		};
	}
	catch {
		my ($e) = @_;
		if ($e->does('InvalidArguemnt')) {
			return res 400 => { message => $e->message }
				if request->is_ajax;
			flash message => "Configuration changed";
			return redirect '/'.$view_id;
		}
		elsif ($e->does('ObjectNotFound')) {
			return res 404 => { message => $e->message }
				if request->is_ajax;
			flash message => "Configuration changed";
			return redirect '/'.$view_id;
		}
		else {
			$e->rethrow;
		}
	}	
};

# CREATE or UPDATE
post '/:view_id/config' => sub {
	my $view_id = params->{view_id} || 0;

	unless (is_admin) {
		return res 403 => { message => 'Permission denied' }
			if request->is_ajax;
		flash error => "Permission denied";
		return redirect '/'.$view_id;
	}

	my $key = params->{config_key};
	my $value = params->{config_value};

	try {
		my $config_id = _create_view_config($view_id, $key, $value);
		return res 200 => { message => "Configuration changed", view_id => $view_id, id => $config_id, key => $key, value => $value }
			if request->is_ajax;
		flash message => "Configuration changed";
		return redirect '/'.$view_id;
	}
	catch {
		my ($e) = @_;
		if ($e->does('InvalidArguemnt')) {
			return res 400 => { message => $e->message }
				if request->is_ajax;
			flash message => "Configuration changed";
			return redirect '/'.$view_id;
		}
		elsif ($e->does('ObjectNotFound')) {
			return res 404 => { message => $e->message }
				if request->is_ajax;
			flash message => "Configuration changed";
			return redirect '/'.$view_id;
		}
		else {
			$e->rethrow;
		}
	}
};

post '/:view_id/config/:config_id/delete' => sub {
	my $view_id = params->{view_id} || 0;
	my $config_id = params->{config_id} || 0;

	unless (is_admin) {
		return res 403 => { message => 'Permission denied' }
			if request->is_ajax;
		flash error => "Permission denied";
		return redirect '/'.$view_id;
	}

	unless (_delete_view_config($view_id, $config_id)) {
		return res 400 => { message => "Invalid arguments" }
			if request->is_ajax;
		flash error => "Invalid arguments";
		return redirect '/'.$view_id;
	}

	return res 200 => { message => "Configdata removed", view_id => $view_id, id => $config_id }
		if request->is_ajax;
	flash message => "Config removed";
	return redirect '/'.$view_id;
};

# "MODEL"
sub _exists_view_config {
	my ($view_id, $config_id) = @_;
	
	raise 'ObjectNotFound' => "View not found"
		unless (_exists_view_config($view_id));

	raise 'InvalidArgument' => "Expected integer config_id"
		unless (looks_like_number($config_id));

	return database->quick_lookup('pt_views_config', {id => $config_id}, 'id');
}

sub _delete_view_config {
	my ($view_id, $config_id) = @_;

	if (looks_like_number($view_id) and looks_like_number($config_id)) {
		return database->quick_delete('pt_views_config', {id => $config_id});
	}

	return undef;
}

# id and (view_id & key) are redundant, as both are qualified as primary keys
# For now, we use the second candidate, so we need valid combination of both, 
# to either update or create, but should switch to first one.
sub _update {
	return _create_view_config(@_);
}

sub _create_view_config {
	my ($view_id, $config_key, $config_value) = @_;

	raise 'ObjectNotFound' => "View not found"
		unless (_exists_view($view_id));

	raise 'InvalidArgument' => "Invalid config key"
		if (not defined $config_key or $config_key !~ /^[a-z0-9][a-z0-9-]*[a-z0-9]$/i);

	raise 'InvalidArgument' => "Invalid config value"
		if (not defined $config_value or $config_value eq '');

	my $exists = database->quick_lookup('pt_views_config', { view_id => $view_id, key => $config_key }, 'id');
	my ($op, $config_id);
	unless ($exists) {
		database->quick_insert('pt_views_config', { view_id => $view_id, key => $config_key, value => $config_value });
		return database->last_insert_id(undef, undef, 'pt_views', 'id');
	}
	else {
		database->quick_update('pt_views_config', { id => $exists }, { value => $config_value });
		return $exists;
	}
}

sub _get_view_config {
	my ($view_id, $config_id) = @_;
	
	raise 'ObjectNotFound' => "View not found"
		unless (_exists_view($view_id));

	if (not defined $config_id or $config_id eq ':ALL') {
		return (database->quick_select('pt_views_config', {view_id => $view_id}, {order_by => 'name'}));
	}
	elsif (looks_like_number($config_id)) {
		return database->quick_select('pt_views', {id => $config_id, view_id => $view_id});
	}
	else {
		raise 'InvalidArgument' => "Expected integer config_id";
	}
}
prefix undef;

1;
