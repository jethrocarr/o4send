--
-- o4send template database schema
--

CREATE DATABASE `o4send` DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;
USE `o4send`;


CREATE TABLE IF NOT EXISTS `app_log` (
  `id` int(11) NOT NULL auto_increment,
  `timestamp` bigint(20) NOT NULL,
  `category` char(20) NOT NULL,
  `message` varchar(255) NOT NULL,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 AUTO_INCREMENT=1 ;

CREATE TABLE IF NOT EXISTS `phones_seen` (
  `id` int(11) NOT NULL auto_increment,
  `timestamp` bigint(20) NOT NULL,
  `bt_phone_mac` char(17) NOT NULL,
  `transfer_filemd5sum` char(32) NOT NULL,
  `transfer_status` char(7) NOT NULL,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 AUTO_INCREMENT=1 ;

