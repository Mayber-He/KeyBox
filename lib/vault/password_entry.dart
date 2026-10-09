import 'package:flutter/material.dart';

class PasswordEntry {
  const PasswordEntry({
    required this.id,
    required this.name,
    required this.username,
    required this.password,
    this.website = '',
    this.notes = '',
    this.category = '个人',
    this.color = const Color(0xFF2C806A),
  });
  final String id, name, username, password, website, notes, category;
  final Color color;
}

List<PasswordEntry> demoPasswords() => [
  PasswordEntry(
    id: 'gmail',
    name: 'Gmail',
    username: 'hello@example.com',
    password: 'Demo-Mail-2026!',
    website: 'https://mail.google.com',
    notes: '个人邮箱 · 示例账号',
    category: '邮箱',
    color: Color(0xFFBF715B),
  ),
  PasswordEntry(
    id: 'github',
    name: 'GitHub',
    username: 'keybox-demo',
    password: 'Demo-GitHub-2026!',
    website: 'https://github.com',
    notes: '开发工具 · 示例账号',
    category: '开发',
    color: Color(0xFF53616C),
  ),
  PasswordEntry(
    id: 'notion',
    name: 'Notion',
    username: 'notes@example.com',
    password: 'Demo-Notes-2026!',
    website: 'https://www.notion.so',
    notes: '记录日常灵感',
    category: '效率',
    color: Color(0xFF8B795F),
  ),
  PasswordEntry(
    id: 'wechat',
    name: '微信',
    username: 'keybox_demo',
    password: 'Demo-Social-2026!',
    notes: '社交账号 · 示例数据',
    category: '社交',
    color: Color(0xFF4E9276),
  ),
  PasswordEntry(
    id: 'aliyun',
    name: '阿里云',
    username: 'cloud@example.com',
    password: 'Demo-Cloud-2026!',
    website: 'https://www.aliyun.com',
    notes: '云服务控制台 · 示例账号',
    category: '开发',
    color: Color(0xFFC5894E),
  ),
  PasswordEntry(
    id: 'figma',
    name: 'Figma',
    username: 'design@example.com',
    password: 'Demo-Design-2026!',
    website: 'https://www.figma.com',
    category: '设计',
    color: Color(0xFF8875A1),
  ),
];
