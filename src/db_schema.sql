CREATE TABLE IF NOT EXISTS `chatmembers` (
  `chat` bigint NOT NULL,
  `user` bigint NOT NULL,
  `moderator` tinyint(1) NOT NULL,
  `notifyok` tinyint(1) NOT NULL DEFAULT 1,
  `notifyon` tinyint(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (`chat`,`user`),
  KEY `chat` (`chat`)
);

CREATE TABLE IF NOT EXISTS `complaints` (
  `id` int NOT NULL AUTO_INCREMENT,
  `chat` bigint NOT NULL,
  `message` int NOT NULL,
  `complainant` bigint NOT NULL,
  `createdat` bigint NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `chat` (`chat`,`message`) USING BTREE
);

CREATE TABLE IF NOT EXISTS `memberships` (
  `chat` bigint NOT NULL,
  `user` bigint NOT NULL,
  `appearance` bigint NOT NULL,
  PRIMARY KEY (`chat`,`user`)
);

CREATE TABLE IF NOT EXISTS `messages` (
  `chat` bigint NOT NULL,
  `message` int NOT NULL,
  `user` bigint NOT NULL,
  `executor` bigint NOT NULL,
  `isspam` int NOT NULL,
  `username` varchar(191) CHARACTER SET utf8mb4 NOT NULL,
  `createdat` bigint NOT NULL DEFAULT 0,
  PRIMARY KEY (`chat`,`message`)
);

CREATE TABLE IF NOT EXISTS `reactions` (
  `chat` bigint NOT NULL,
  `message` int NOT NULL,
  `user` bigint NOT NULL,
  `executor` bigint NOT NULL,
  `isspam` int NOT NULL,
  `username` varchar(191) CHARACTER SET utf8mb4 NOT NULL,
  `createdat` bigint NOT NULL DEFAULT 0,
  PRIMARY KEY (`chat`,`user`)
);

CREATE TABLE IF NOT EXISTS `users` (
  `id` bigint NOT NULL,
  `appearance` bigint NOT NULL,
  `name` varchar(256) NOT NULL,
  `rate` int NOT NULL,
  `spammer` int NOT NULL,
  PRIMARY KEY (`id`)
);
