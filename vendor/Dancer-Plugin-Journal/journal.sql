DROP TABLE IF EXISTS `journal_tango`;
CREATE TABLE IF NOT EXISTS `journal_tango` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `author` varchar(64) COLLATE utf8_unicode_ci NOT NULL,
  `object` varchar(32) COLLATE utf8_unicode_ci NOT NULL,
  `source` varchar(64) COLLATE utf8_unicode_ci NOT NULL,
  `intent` enum('READ','DELETE','UPDATE','CREATE','LOG') COLLATE utf8_unicode_ci NOT NULL,
  `old_data` text COLLATE utf8_unicode_ci NOT NULL,
  `old_date_id` int(11) NOT NULL,
  `new_data` text COLLATE utf8_unicode_ci NOT NULL,
  `when` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `message` int(11) NOT NULL,
  `address` text COLLATE utf8_unicode_ci NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB  DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;
