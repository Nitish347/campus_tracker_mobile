enum UserRole { parent, driver }

extension UserRoleLabel on UserRole {
  String get label => switch (this) {
    UserRole.parent => 'Parent',
    UserRole.driver => 'Driver',
  };
}
