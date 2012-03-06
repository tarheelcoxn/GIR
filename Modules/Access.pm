package Modules::Access;

## TODO:
## - show access for other users
## - register
## - change password?

#######
## PERL SETUP
#######
use strict;
use lib ('./', '../Main/');

#######
## INCLUDES
#######
use Database::MySQL;

sub new()
{
	my $pkg = shift;
	my $obj = { };
	bless $obj, $pkg;
	return $obj;
}

sub register()
{
	my $this = shift;

	&Modules::register_action('show access', \&Modules::Access::show_access);
	&Modules::register_action('add access', \&Modules::Access::add_access);
	&Modules::register_action('remove access', \&Modules::Access::remove_access);
}

sub show_access($)
{
	my $message = shift;

	# Only reply to this privately
	return if $message->is_public();

	my $db = new Database::MySQL;
	$db->init($Bot::config->{'database'}->{'user'}, $Bot::config->{'database'}->{'password'}, $Bot::config->{'database'}->{'name'});

	my $user = $message->from();
	my $isSelf = 1;

	if ($message->message()) {
		$user = $message->message();
		$isSelf = 0;
	}

	# Look up access for this user
	my $query = qq~
		SELECT name
		FROM access_permissions p
		LEFT JOIN access_user_permissions up ON up.permission_id = p.id
		WHERE up.user_id = (SELECT id FROM access_users WHERE nick = ?)
	~;
	$db->prepare($query);
	my $sth = $db->execute($user);

	my @permissions;
	while (my $permission = $sth->fetchrow_hashref()) {
		push @permissions, $permission->{'name'};
	}

	$user = $isSelf ? 'You' : $user;

	if (scalar(@permissions) > 0) {
		return sprintf('%s %s the following permissions: %s', $user, $isSelf ? 'have' : 'has', join(', ', @permissions));
	} else {
		return sprintf('%s do%s not have any special permissions.', $user, $isSelf ? '' : 'es');
	}
}

#######
## CHECK ACCESS
## Takes a nick, password, and access, and returns 1 if the user has that access (and a correct password).
## This function is intended to be called from other modules.
#######
sub check_access($$$)
{
	my ($user, $password, $access) = @_;

	my $db = new Database::MySQL;
	$db->init($Bot::config->{'database'}->{'user'}, $Bot::config->{'database'}->{'password'}, $Bot::config->{'database'}->{'name'});

	# Look up user
	my $query = qq~
		SELECT id
		FROM access_users
		WHERE nick = ? AND password = ?
	~;
	$db->prepare($query);
	my $sth = $db->execute($user, $password);
	my $user_info = $sth->fetchrow_hashref();

	unless ($user_info && $user_info->{'id'}) {
		Bot::debug("Modules::Access::check_access: User '%s' not found.", $user);
		return 0;
	}

	# Check for access
	$query = qq~
		SELECT up.permission_id
		FROM access_user_permissions up
		LEFT JOIN access_permissions p ON p.id = up.permission_id
		WHERE up.user_id = ? AND p.name = ?
	~;
	$db->prepare($query);
	$sth = $db->execute($user_info->{'id'}, $access);
	$access = $sth->fetchrow_hashref();

	if ($access && $access->{'permission_id'}) {
		return 1;
	}
	Bot::debug("Modules::Access::check_access: User %s doesn't have '%s' permission", $user_info->{'id'}, $access);
	return 0;
}

sub add_access($)
{
	my $message = shift;

	# Only reply to this privately
	return if $message->is_public();

	my $db = new Database::MySQL;
	$db->init($Bot::config->{'database'}->{'user'}, $Bot::config->{'database'}->{'password'}, $Bot::config->{'database'}->{'name'});

	# Get the parts; syntax is <password> <user> <access>
	my $user = $message->from();
	my ($password, $target_user, $to_add) = split(/\s+/, $message->message(), 3);

	my $allowed = &check_access($user, $password, 'add_access');

	unless ($allowed) {
		return "You don't have permission to do that, $user!";
	}

	# Check if the access exists
	my $query = qq~
		SELECT id
		FROM access_permissions
		WHERE name = ?
	~;
	$db->prepare($query);
	my $sth = $db->execute($to_add);
	my $access = $sth->fetchrow_hashref();

	# Add it if it doesn't
	unless ($access && $access->{'id'}) {
		$query = qq~
			INSERT INTO access_permissions
			(name)
			VALUES
			(?)
		~;
		$db->prepare($query);
		$db->execute($to_add);

		$access = $db->insert_id();
	} else {
		$access = $access->{'id'};
	}

	# Look up user
	$query = qq~
		SELECT id
		FROM access_users
		WHERE nick = ?
	~;
	$db->prepare($query);
	$sth = $db->execute($target_user);
	my $user_info = $sth->fetchrow_hashref();

	unless ($user_info && $user_info->{'id'}) {
		return "$target_user isn't registered.";
	}

	# Check if user already has that access
	$query = qq~
		SELECT p.id
		FROM access_permissions p
		LEFT JOIN access_user_permissions up ON up.permission_id = p.id
		WHERE up.user_id = ? AND p.id = ?
	~;
	$db->prepare($query);
	$sth = $db->execute($user_info->{'id'}, $access);
	my $curr_access = $sth->fetchrow_hashref();

	if ($curr_access && $curr_access->{'id'}) {
		return "$target_user already has the permission '$to_add'";
	}

	# Add permission to user
	$query = qq~
		INSERT INTO access_user_permissions
		(user_id, permission_id)
		VALUES
		(?, ?)
	~;
	$db->prepare($query);
	$db->execute($user_info->{'id'}, $access);

	return 'Permission added';
}

sub remove_access($)
{
	my $message = shift;

	# Only reply to this privately
	return if $message->is_public();

	my $db = new Database::MySQL;
	$db->init($Bot::config->{'database'}->{'user'}, $Bot::config->{'database'}->{'password'}, $Bot::config->{'database'}->{'name'});

	# Get the parts; syntax is <password> <user> <access>
	my $user = $message->from();
	my ($password, $target_user, $to_remove) = split(/\s+/, $message->message(), 3);

	my $allowed = &check_access($user, $password, 'remove_access');

	unless ($allowed) {
		return "You don't have permission to do that, $user!";
	}

	# Look up target user
	my $query = qq~
		SELECT id
		FROM access_users
		WHERE nick = ?
	~;
	$db->prepare($query);
	my $sth = $db->execute($target_user);
	my $user_info = $sth->fetchrow_hashref();

	unless ($user_info && $user_info->{'id'}) {
		return "$target_user isn't registered, $user";
	}

	# Look up permission
	$query = qq~
		SELECT p.id
		FROM access_permissions p
		LEFT JOIN access_user_permissions up ON up.permission_id = p.id
		WHERE p.name = ? AND up.user_id = ?
	~;
	$db->prepare($query);
	$sth = $db->execute($to_remove, $user_info->{'id'});
	my $permission = $sth->fetchrow_hashref();

	unless ($permission && $permission->{'id'}) {
		return "$target_user doesn't have that permission, $user";
	}

	# Remove the permission
	$query = qq~
		DELETE FROM access_user_permissions
		WHERE user_id = ? AND permission_id = ?
	~;
	$db->prepare($query);
	$db->execute($user_info->{'id'}, $permission->{'id'});

	return 'Permission removed';
}

1;
