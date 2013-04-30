CREATE TABLE IF NOT EXISTS `pt_views` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(64) NOT NULL,
  `clients` text NOT NULL,
  `destinations` text NOT NULL,
  `recursive_only` bit(1) NOT NULL DEFAULT b'0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 AUTO_INCREMENT=1 ;

CREATE TABLE IF NOT EXISTS `pt_views_acl` (
  `user_id` int(11) NOT NULL,
  `view_id` int(11) NOT NULL,
  PRIMARY KEY (`user_id`,`view_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `pt_views_domains_map` (
  `domain_id` int(11) NOT NULL,
  `view_id` int(11) NOT NULL,
  PRIMARY KEY (`domain_id`,`view_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `pt_views_metadata` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `view_id` int(11) NOT NULL,
  `key` varchar(32) NOT NULL,
  `value` varchar(256) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `view_id` (`view_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 AUTO_INCREMENT=1 ;
