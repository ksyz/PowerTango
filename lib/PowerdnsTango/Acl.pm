package PowerdnsTango::Acl;
use Dancer ':syntax';
use Dancer::Plugin::Database;
use Dancer::Session::Storable;
use Scalar::Util qw(looks_like_number);

use base "Exporter";

our @EXPORT = qw(user_acl);
our $VERSION = '0.1';


# To confuse, 
# 1 => no access
# 0 => access granted
sub user_acl {
	my ($obj_id, $obj_type) = @_;
	my $user_type = session 'user_type';
	my $user_id = session 'user_id';
	my $acl;
	my $check_acl;

	return 0 
		if ($user_type eq 'admin');

	return 1
		if (not defined $obj_id or !looks_like_number($obj_id) or not defined $obj_type);

	if ($obj_type eq 'domain') {
		$acl = database->prepare("SELECT COUNT(id) AS count FROM domains_acl_tango WHERE domain_id = ? AND user_id = ?");
	}
	elsif ($obj_type eq 'template') {
		$acl = database->prepare("SELECT COUNT(id) AS count FROM templates_acl_tango WHERE template_id = ? AND user_id = ?");
	}
	else {
		# this is more severe, as we probably did som type there
		die 'Invalid ACL object type';
	}

	$acl->execute($obj_id, $user_id);
	$check_acl = $acl->fetchrow_hashref;

	return 0 
		if $check_acl->{count} > 0;

	return 1;
};

1;
