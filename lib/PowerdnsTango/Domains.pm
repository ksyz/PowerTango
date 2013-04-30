package PowerdnsTango::Domains;
use Dancer ':syntax';
use Dancer::Plugin::Database;
use Dancer::Plugin::FlashMessage;
use Dancer::Plugin::Res;
use Dancer::Session::Storable;
use Dancer::Template::TemplateToolkit;
use Dancer::Plugin::Ajax;
use DateTime;
use Data::Page;
use Data::Validate::IP qw(is_ipv4 is_ipv6);
use PowerdnsTango::Acl qw(user_acl);
use PowerdnsTango::Validate::Records qw(check_valid_masters is_domain);
use strict;
use warnings;

our $VERSION = '0.3';


any ['get', 'post'] => '/domains' => sub {
	my $load_page = params->{p} || 1;
	my $results_per_page = params->{r} || 25;
	my $search = params->{domain_search} || undef;
	my ($st_domain_count, $st_domains, $page, $display, $count);
	my $user_type = session 'user_type';
	my $user_id = session 'user_id';

	# Requested search
	if (request->method() eq "POST" && defined $search) {
		if ($user_type eq 'admin') {
			$st_domain_count = database->prepare('SELECT COUNT(id) AS count FROM domains WHERE name LIKE ?');
			$st_domain_count->execute("%$search%");
		}
		else {
			$st_domain_count = database->prepare('SELECT COUNT(domains.id) AS count FROM domains AS d LEFT JOIN domains_acl_tango AS da ON (d.id = da.domain_id) WHERE da.user_id = ? AND d.name LIKE ?');
			$st_domain_count->execute($user_id, "%$search%");
		}
	}
	# requested list all
	else {
		if ($user_type eq 'admin') {
			$st_domain_count = database->prepare('SELECT COUNT(id) AS count FROM domains');
			$st_domain_count->execute();
		}
		else {
			$st_domain_count = database->prepare('SELECT COUNT(d.id) FROM domains AS d LEFT JOIN domains_acl_tango AS da ON (d.id = da.domain_id) WHERE da.user_id = ?');
			$st_domain_count->execute($user_id);
		}
	}

	$count = $st_domain_count->fetchrow_hashref;
	if ($count->{count}) {
		# Pager helper
		$page = Data::Page->new();
		$page->total_entries($count->{'count'});
		$page->entries_per_page($results_per_page);
		$page->current_page($load_page);

		$display = ($page->entries_per_page * ($page->current_page - 1));
		$load_page = $page->last_page if ($load_page > $page->last_page);
		$load_page = $page->first_page if ($load_page == 0);

		if (request->method() eq "POST" && defined $search) {
			if ($user_type eq 'admin') {
				$st_domains = database->prepare('SELECT * FROM domains WHERE name LIKE ? LIMIT ? OFFSET ?');
				$st_domains->execute("%$search%", $page->entries_per_page, $display);
			}
			else {
				$st_domains = database->prepare('SELECT d.* FROM domains AS d LEFT JOIN domains_acl_tango AS da ON (d.id = da.domain_id) WHERE da.user_id = ? AND d.name LIKE ? LIMIT ? OFFSET ?');
				$st_domains->execute($user_id, "%$search%", $page->entries_per_page, $display);
			}

			flash message => "Domain search found $count->{'count'} matches" if ($count->{'count'} >= 1);
		}
		else {
			if ($user_type eq 'admin') {
				$st_domains = database->prepare('SELECT * FROM domains LIMIT ? OFFSET ?');
				$st_domains->execute($page->entries_per_page, $display);
			}
			else {
				$st_domains = database->prepare('SELECT d.* FROM domains AS d LEFT JOIN domains_acl_tango AS da ON (d.id = da.domain_id) WHERE da.user_id = ? LIMIT ? OFFSET ?');
				$st_domains->execute($user_id, $page->entries_per_page, $display);
			}
		}
	}
	else {
		flash error => "Domain search found no match";
	}

	my $st_templates;

	if ($user_type eq 'admin') {
		$st_templates = database->prepare('SELECT * FROM templates_tango');
		$st_templates->execute();
	}
	else {
		$st_templates = database->prepare(' SELECT t.* FROM templates_tango AS t LEFT JOIN templates_acl_tango AS ta ON (t.id = ta.template_id) WHERE ta.user_id = ?');
		$st_templates->execute($user_id);
	}
	template('domains', {
		domains => ($st_domains ? $st_domains->fetchall_hashref('id') : {}),
		templates => ($st_templates ? $st_templates->fetchall_hashref('id') : {}),
		page => $load_page, 
		results => $results_per_page, 
		previouspage => ($load_page - 1), 
		nextpage => ($load_page + 1), 
		lastpage => ($page ? $page->last_page : 0),
	});
};

# any [ 'get', 'post' ] => '/domains/add' => sub {
# ajax '/domains/add' => sub {
post '/domains/add' => sub {
	my $domain = params->{add_domain_name} || 0;
	my $type = params->{add_domain_type} || 0;
	my $master = params->{add_master_addr} || '';
	my $template_id = params->{add_domain_template} || 0;
	my $user_type = session 'user_type';
	my $user_id = session 'user_id';
	my $dt = DateTime->now;
	my ($year,$month,$day) = split(/-/, $dt->ymd('-'));
	my $success = 0;
	my $sth;

	$domain =~ s/\s//g;
	$master =~ s/\s//g 
		if (defined $master);

	unless (is_domain($domain)) {
		# status 400;
		# return { stat => 'fail', message => "Invalid domain name"};
		return res 400 => to_json { stat => 'fail', message => "Invalid domain name"};
	}

	unless ($user_type eq 'admin') {
		my $user_domain_limit = database->quick_select('users_tango', { id => $user_id });
		$sth = database->prepare("SELECT COUNT(id) AS count FROM domains_acl_tango WHERE user_id = ?");
		$sth->execute($user_id);
		my $owned_domains = $sth->fetchrow_hashref;

		return res 404 => {
			stat => 'fail',
			message => "You have reached your domain limit of $user_domain_limit->{domain_limit}"
		} if ($owned_domains->{count} >= $user_domain_limit->{domain_limit});
	}

	return res 409 => { stat => 'fail', message => "Domain $domain already exists"}
		if database->quick_lookup('domains', {'name' => $domain}, 'id');

	my $domain_id = undef; # ID of new domain

	if ($type eq 'NATIVE' || $type eq 'MASTER') {
		$success = database->quick_insert('domains', 
			{ name => $domain, type => $type, notified_serial => ($year . $month . $day . 0 . 1) });
	}
	elsif ($type eq 'SLAVE') {
		# checking for valid list of masters (check also rewrites value)
		return res 400 => { stat => 'fail', 
			message => "A vaild master address or list of ".
				"comma separated master addresses must be provided" 
		} unless check_valid_masters(\$master);

		$success = database->quick_insert('domains', 
			{ name => $domain, type => $type, master => $master, 
			notified_serial => ($year . $month . $day . 0 . 1) });
	}

	if ($success) {
		$domain_id = database->last_insert_id(undef, undef, 'domains', 'id');
		return 501 => { stat => 'fail', message => 'last_insert_id failed' }
			unless defined $domain_id;
		database->quick_insert('domains_acl_tango', { user_id => $user_id, domain_id => $domain_id });
	}
	else {
		return 501 => { stat => 'fail', message => 'Domain insert query failed' };
	}

	if ($type ne 'SLAVE' && $success) {
		# Applying RR from template
		if ($template_id != 0) {
			my $templates_records = database->prepare('SELECT * FROM templates_records_tango WHERE template_id = ?');
			$templates_records->execute($template_id);

			while (my $template_row = $templates_records->fetchrow_hashref) {
				$template_row->{name} =~ s/\%(\s)?(zone|domain|host)(\s)?\%/$domain/i;
				$template_row->{name} =~ s/\%(\s)?(.+?)(\s)?\%//i;
				$template_row->{content} =~ s/\%(\s)?(zone|domain|host)(\s)?\%/$domain/i;
				$template_row->{content} =~ s/\%(\s)?(.+?)(\s)?\%//i;
				
				database->quick_insert('records', { 
					domain_id => $domain_id, name => $template_row->{name}, 
					type => $template_row->{type}, content => $template_row->{content}, 
					ttl => $template_row->{ttl}, prio => $template_row->{prio}, 
					change_date => ($year . $month . $day . 0 . 1)
				});
			}
		}

		# Applying defaul SOA
		my $default_soa = database->quick_select('admin_default_soa_tango', {});

		if (defined $default_soa->{name_server} && defined $default_soa->{contact} 
			&& defined $default_soa->{refresh} && defined $default_soa->{retry} 
			&& defined $default_soa->{expire} && defined $default_soa->{minimum} 
			&& defined $default_soa->{ttl}) {
			my $content = ($default_soa->{name_server} . " " . $default_soa->{contact} . " " . $year . $month . $day . 0 . 1 . " " . $default_soa->{refresh} . " " . $default_soa->{retry} . " " . $default_soa->{expire} . " " . $default_soa->{minimum});
			
			database->quick_insert('records', { 
				domain_id => $domain_id, name => $domain, type => 'SOA', 
				content => $content, ttl => $default_soa->{ttl}, 
				change_date => ($year . $month . $day . 0 . 1)
			});
		}
	}

	return res 200 => {
		stat => 'ok',
		id => $domain_id,
		message => "Domain $domain added",
		name => $domain,
		type => $type,
		master => $master,
	};
};

post '/domains/add/bulk' => sub
{
	my @domain = do {local $_ = params->{add_bulk_domain_name}; split};
	my $type = params->{add_bulk_domain_type} || 0;
	my $master = params->{add_bulk_master_addr};
	my $template_id = params->{add_bulk_domain_template} || 0;
	my $count = @domain;
        my $success = 0;
        my $error = 0;
	my $status;
	my $dt = DateTime->now;
	my ($year,$month,$day) = split(/-/, $dt->ymd('-'));
        my $user_type = session 'user_type';
        my $user_id = session 'user_id';


	for my $domain (@domain)
	{
		my $msg;
		my $err;

                $domain =~ s/\s//g;
                $master =~ s/\s//g if (defined $master);


		if (! is_domain($domain))
        	{
			$err = template 'error-format', { error => "Domain $domain is not a valid domain name" }, { layout => undef };
			$status .= $err;
			$error++;

			next;
		}


        	my $sth = database->prepare("select count(name) as count from domains where name = ?");
        	$sth->execute($domain);
        	my $count = $sth->fetchrow_hashref;


        	if ($user_type ne 'admin')
        	{
                	my $user_domain_limit = database->quick_select('users_tango', { id => $user_id });
                	$sth = database->prepare("select count(id) as count from domains_acl_tango where user_id = ?");
                	$sth->execute($user_id);
                	my $owned_domains = $sth->fetchrow_hashref;


                	if ($owned_domains->{count} >= $user_domain_limit->{domain_limit})
                	{
                        	$err = template 'error-format', { error => "Domain $domain was not added, you have reached your domain limit" }, { layout => undef };
                        	$status .= $err;
                        	$error++;
				next;
                	}
        	}


		if ($count->{count} != 0)   
        	{
			$err = template 'error-format', { error => "Domain $domain already exists" }, { layout => undef };
			$status .= $err;
			$error++;
        	}
        	elsif (is_domain($domain) && ($type =~ m/^NATIVE$/i || $type =~ m/^MASTER$/i))
        	{
                	database->quick_insert('domains', { name => $domain, type => $type, notified_serial => ($year . $month . $day . 0 . 1) });
                	my $get_id = database->quick_select('domains', { name => $domain });
                	database->quick_insert('domains_acl_tango', { user_id => $user_id, domain_id => $get_id->{id} });
                        $msg = template 'message-format', { message => "Domain $domain added" }, { layout => undef };
                        $status .= $msg;
			$success++;
        	}
        	elsif (is_domain($domain) && ($type =~ m/^SLAVE$/i) && check_valid_masters(\$master))
        	{
                	database->quick_insert('domains', { name => $domain, type => $type, master => $master, notified_serial => ($year . $month . $day . 0 . 1) });
                	my $get_id = database->quick_select('domains', { name => $domain });
                	database->quick_insert('domains_acl_tango', { user_id => $user_id, domain_id => $get_id->{id} });
                        $msg = template 'message-format', { message => "Domain $domain added" }, { layout => undef };
                        $status .= $msg;
			$success++;
        	}
        	elsif (is_domain($domain) && ($type =~ m/^SLAVE$/i) && !check_valid_masters($master))
        	{
                        $err = template 'error-format', { error => "Domain $domain was not added, a valid master address must be provided" }, { layout => undef };
                        $status .= $err;
			$error++;
        	}

        
		if ($template_id != 0 && $success != 0 && $type !~ m/^SLAVE$/i)
        	{
                	my $domain_id = database->quick_select('domains', { name => $domain });
                	my $templates_records = database->prepare('select * from templates_records_tango where template_id = ?');
                	$templates_records->execute($template_id);


                	while (my $template_row = $templates_records->fetchrow_hashref)
                	{
                       		$template_row->{name} =~ s/\%(\s)?(zone|domain|host)(\s)?\%/$domain/i;
                       		$template_row->{name} =~ s/\%(\s)?(.+?)(\s)?\%//i;
                       		$template_row->{content} =~ s/\%(\s)?(zone|domain|host)(\s)?\%/$domain/i;
                       		$template_row->{content} =~ s/\%(\s)?(.+?)(\s)?\%//i;

                       		database->quick_insert('records', { domain_id => $domain_id->{id}, name => $template_row->{name}, type => $template_row->{type}, content => $template_row->{content},
                       		ttl => $template_row->{ttl}, prio => $template_row->{prio}, change_date => ($year . $month . $day . 0 . 1) });
               		}
       		}
		elsif ($type !~ m/^SLAVE$/i)
		{	
                	my $domain_id = database->quick_select('domains', { name => $domain });
                	my $default_soa = database->quick_select('admin_default_soa_tango', {});

			if (defined $default_soa->{name_server} && defined $default_soa->{contact} && defined $default_soa->{refresh} && defined $default_soa->{retry} && defined $default_soa->{expire} && defined 
			$default_soa->{minimum} && defined $default_soa->{ttl})
			{
                		my $content = ($default_soa->{name_server} . " " . $default_soa->{contact} . " " . $year . $month . $day . 0 . 1 . " " . $default_soa->{refresh} . " " . $default_soa->{retry} . " " . $default_soa->{expire} . " " . $default_soa->{minimum});
                		database->quick_insert('records', { domain_id => $domain_id->{id}, name => $domain, type => 'SOA', content => $content, ttl => $default_soa->{ttl}, change_date => ($year . $month . $day . 0 . 1) });
			}
        	}
	}


	if (($success == $count) && ($count ne 0))
	{
		flash message => "Domains added";
	}
	elsif ($success >= 1)
	{
		flash error => "Domainis added with some failures";
	}
	else
	{
		flash error => "Failed to add domains, please ensure the domain(s) provided are valid";
	}


	flash detail => $status;


	return redirect '/domains';
};

ajax '/domains/delete/id/:id' => sub {
	my $id = params->{id} || undef;

	return { stat => 'fail', message => 'Missing domain ID' }
		unless defined $id;

	my $perm = user_acl($id, 'domain');
	return { stat => 'fail', message => 'Permission denied' }
		if ($perm == 1);
	
	database->quick_delete('domains', { id => $id });
	database->quick_delete('records', { domain_id => $id });
	database->quick_delete('domains_acl_tango', { domain_id => $id });

	return { stat => 'ok', id => $id, message => "Domain deleted" };
};

ajax '/domains/update' => sub {
	my $id = params->{id} || undef;
	my $domain = params->{name} || '';
	my $type = params->{type} || undef;
	my $master = params->{master} || '';
	
	my $perm = user_acl($id, 'domain');
	my $user_type = session 'user_type';
	my $user_id = session 'user_id';

	return { stat => 'fail', message => 'Permission denied' }
		if ($perm == 1);

	return { stat => 'fail', message => 'Invalid domain name' }
		unless is_domain($domain);

	my $domain_exists = database->quick_lookup('domains', {name => $domain}, 'name');
	my $old_domain = database->quick_select('domains', {id => $id});

	if (defined $domain_exists and defined $old_domain and $old_domain->{name} ne $domain) {
		# we are not just updating other params
		return { stat => 'fail', message => "Domain already exists" };
	}
	elsif ($type eq 'NATIVE' or $type eq 'MASTER') {
		database->quick_update('domains', { id => $id }, { name => $domain, type => $type, master => undef });
		my @domain_records = database->quick_select('records', {domain_id => $id});

		for my $record (@domain_records) {
			$record->{name} =~ s/$old_domain->{name}/$domain/i;
			$record->{content} =~ s/$old_domain->{name}/$domain/i;
			database->quick_update('records', { id => $record->{id} }, 
				{ name => $record->{name}, content => $record->{content} });
		}
	}
	elsif ($type eq 'SLAVE') {
		 # checking for valid list of masters (check also rewrites value)
		return { stat => 'fail', 
			message => "A vaild master address or list of ".
				"comma separated master addresses must be provided" 
		} unless check_valid_masters(\$master);

		database->quick_update('domains', { id => $id }, { name => $domain, type => $type, master => $master });
		database->quick_delete('records', { domain_id => $id });
	}
	else {
		return { stat => 'fail', message => 'Domain update failed' };
	}

	return { stat => 'ok', message => 'Domain updated', id => $id, name => $domain, 
		type => $type, master => $master };
};


ajax '/domains/get' => sub {
	my $id = params->{id} || undef;
	my $perm = user_acl($id, 'domain');

	return { stat => 'fail', message => 'Missing domain ID' }
		unless ($id);

	return { stat => 'fail', message => 'Permission denied' }
		if ($perm == 1);

	my $domain = database->quick_select('domains', { id => $id });

	return { 
		stat => 'ok', id => $id, name => $domain->{name}, type => $domain->{type}, 
		master => $domain->{master} 
	};
};


true;
