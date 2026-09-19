import 'package:flutter_test/flutter_test.dart';
import 'package:espo_worker_app/models/chat_room.dart';
import 'package:espo_worker_app/models/chat_message.dart';

void main() {
  group('ChatRoom Model Tests', () {
    test('Correctly extracts partner name in 1:1 direct chat via members and partnerUserId', () {
      final json = {
        'id': 'room_123',
        'name': 'Jan Philipp von Czapiewski ↔ Max Mustermann',
        'type': 'direct',
        'lastMessageText': 'Hallo, alles klar!',
        'lastMessageAt': '2026-09-19 12:00:00',
        'unreadCount': 2,
        'partnerUserId': 'user_partner',
        'partnerCompany': 'MB Security Concept & Consulting GmbH',
        'members': [
          {'id': 'user_me', 'name': 'Jan Philipp von Czapiewski', 'avatarId': null},
          {'id': 'user_partner', 'name': 'Max Mustermann', 'avatarId': 'att_456'},
        ],
      };

      final room = ChatRoom.fromJson(json);

      expect(room.id, equals('room_123'));
      expect(room.type, equals('direct'));
      expect(room.partnerUserId, equals('user_partner'));
      expect(room.partnerCompany, equals('MB Security Concept & Consulting GmbH'));
      expect(room.partnerAvatarId, equals('att_456'));
      expect(room.unreadCount, equals(2));

      // Test display name resolution
      final displayName = room.getDisplayName('user_me', 'Jan Philipp von Czapiewski');
      expect(displayName, equals('Max Mustermann'));
    });

    test('Falls back cleanly using arrow separator if partner is not in members list', () {
      final json = {
        'id': 'room_456',
        'name': 'Jan Philipp von Czapiewski ↔ Sarah Schmidt',
        'type': 'direct',
        'members': <dynamic>[],
      };

      final room = ChatRoom.fromJson(json);

      final displayName = room.getDisplayName('user_me', 'Jan Philipp von Czapiewski');
      expect(displayName, equals('Sarah Schmidt'));
    });

    test('Retains original name for group chats', () {
      final json = {
        'id': 'room_grp',
        'name': 'Einsatzleitung Großevent',
        'type': 'group',
        'members': [
          {'id': 'user_1', 'name': 'Mitarbeiter 1'},
          {'id': 'user_2', 'name': 'Mitarbeiter 2'},
        ],
      };

      final room = ChatRoom.fromJson(json);

      final displayName = room.getDisplayName('user_me', 'Jan Philipp von Czapiewski');
      expect(displayName, equals('Einsatzleitung Großevent'));
    });
  });

  group('ChatMessage Model Tests', () {
    test('Parses complete ChatMessage with replyTo and attachments', () {
      final json = {
        'id': 'msg_001',
        'body': 'Hier ist das Wachbuch-Foto',
        'chatRoomId': 'room_123',
        'createdById': 'user_me',
        'createdByName': 'Jan Philipp',
        'createdAt': '2026-09-19 12:05:00',
        'isRead': true,
        'attachmentId': 'att_999',
        'attachmentType': 'image/jpeg',
        'attachmentName': 'foto.jpg',
        'replyTo': {
          'id': 'msg_000',
          'body': 'Bitte Foto hochladen',
          'createdByName': 'Einsatzleiter',
        },
      };

      final msg = ChatMessage.fromJson(json);

      expect(msg.id, equals('msg_001'));
      expect(msg.body, equals('Hier ist das Wachbuch-Foto'));
      expect(msg.isRead, isTrue);
      expect(msg.attachmentId, equals('att_999'));
      expect(msg.attachmentType, equals('image/jpeg'));
      expect(msg.replyTo, isNotNull);
      expect(msg.replyTo!['body'], equals('Bitte Foto hochladen'));
    });
  });

  group('Chat Deduplication and Reconciliation Logic', () {
    test('Pending optimistic message is seamlessly reconciled by incoming server message', () {
      final messages = <ChatMessage>[
        ChatMessage(
          id: 'msg_old',
          body: 'Vorherige Nachricht',
          chatRoomId: 'room_123',
          createdById: 'user_partner',
          createdAt: '2026-09-19 11:59:00',
        ),
        ChatMessage(
          id: 'temp_123456789',
          body: 'Neue gesendete Nachricht',
          chatRoomId: 'room_123',
          createdById: 'user_me',
          createdAt: '2026-09-19 12:00:00',
        ),
      ];

      // Simulated server response from getMessages polling
      final incomingFromServer = [
        ChatMessage(
          id: 'msg_old',
          body: 'Vorherige Nachricht',
          chatRoomId: 'room_123',
          createdById: 'user_partner',
          createdAt: '2026-09-19 11:59:00',
        ),
        ChatMessage(
          id: 'real_msg_from_server_789',
          body: 'Neue gesendete Nachricht',
          chatRoomId: 'room_123',
          createdById: 'user_me',
          createdAt: '2026-09-19 12:00:01',
        ),
      ];

      final existingIds = messages.map((m) => m.id).toSet();
      final newMsgs = <ChatMessage>[];

      for (final m in incomingFromServer) {
        if (existingIds.contains(m.id)) continue;

        final tempIndex = messages.indexWhere(
          (temp) => temp.id.startsWith('temp_') && temp.body == m.body && temp.createdById == m.createdById,
        );
        if (tempIndex != -1) {
          messages[tempIndex] = m;
        } else {
          newMsgs.add(m);
        }
      }
      messages.addAll(newMsgs);

      // Verify no duplicates and the temp ID was replaced by the server ID
      expect(messages.length, equals(2));
      expect(messages[1].id, equals('real_msg_from_server_789'));
      expect(messages.any((m) => m.id.startsWith('temp_')), isFalse);
    });
  });
}
