import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'features/auth/auth_controller.dart';
import 'features/auth/forgot_password_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/auth/reset_password_screen.dart';
import 'features/auth/verify_email_screen.dart';
import 'features/admin/admin_reports_screen.dart';
import 'features/admin/admin_review_screens.dart';
import 'features/community/blocked_users_screen.dart';
import 'features/community/community_feed_screen.dart';
import 'features/community/create_post_screen.dart';
import 'features/community/my_posts_screen.dart';
import 'features/community/notifications_screen.dart';
import 'features/cooking/cooking_screen.dart';
import 'features/cooking/voice_lab_screen.dart';
import 'features/face/face_enroll_screen.dart';
import 'features/face/face_login_screen.dart';
import 'features/home/main_shell.dart';
import 'features/lucky/lucky_meal_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/recipes/recipe_detail_screen.dart';
import 'features/recipes/recipe_list_screen.dart';
import 'features/tastes/tastes_screen.dart';

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Điều hướng theo trạng thái đăng nhập: chưa đăng nhập chỉ vào được /login, /register.
GoRouter createRouter(AuthController auth) {
  const publicPaths = {
    '/login',
    '/register',
    '/verify-email',
    '/forgot-password',
    '/reset-password',
    '/face-login',
  };

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/',
    refreshListenable: auth,
    redirect: (context, state) {
      final path = state.matchedLocation;
      switch (auth.status) {
        case AuthStatus.unknown:
          return path == '/splash' ? null : '/splash';
        case AuthStatus.unauthenticated:
          return publicPaths.contains(path) ? null : '/login';
        case AuthStatus.authenticated:
          // Người dùng chưa được hỏi khẩu vị thì hỏi một lần trước khi vào app
          if (auth.user?.needsTastes == true) return path == '/tastes' ? null : '/tastes';
          if (publicPaths.contains(path) || path == '/splash') return '/';
          // Server vẫn kiểm tra quyền admin; đây chỉ để user thường không thấy màn duyệt
          if (path.startsWith('/admin') && auth.user?.isAdmin != true) return '/';
          return null;
      }
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (_, _) =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(
        path: '/verify-email',
        builder: (_, state) =>
            VerifyEmailScreen(email: state.uri.queryParameters['email'] ?? ''),
      ),
      GoRoute(
        path: '/tastes',
        builder: (_, state) =>
            TastesScreen(editing: state.uri.queryParameters['edit'] == '1'),
      ),
      GoRoute(path: '/face-login', builder: (_, _) => const FaceLoginScreen()),
      GoRoute(path: '/face-enroll', builder: (_, _) => const FaceEnrollScreen()),
      // Màn duyệt bài của admin; redirect ở trên đưa người không phải admin về trang chủ
      GoRoute(
        path: '/admin/recipes/new',
        builder: (_, _) => const CreatePostScreen(systemRecipe: true),
      ),
      GoRoute(
        path: '/admin/review',
        builder: (_, _) => const AdminReviewListScreen(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, state) => AdminReviewDetailScreen(
              recipeId: int.parse(state.pathParameters['id']!),
            ),
          ),
        ],
      ),
      GoRoute(path: '/admin/reports', builder: (_, _) => const AdminReportsScreen()),
      GoRoute(path: '/notifications', builder: (_, _) => const NotificationsScreen()),
      GoRoute(path: '/blocked-users', builder: (_, _) => const BlockedUsersScreen()),
      // Màn thử nhận dạng giọng nói, chỉ có ở bản debug
      if (kDebugMode)
        GoRoute(path: '/voice-lab', builder: (_, _) => const VoiceLabScreen()),
      GoRoute(
        path: '/forgot-password',
        builder: (_, _) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (_, state) =>
            ResetPasswordScreen(email: state.uri.queryParameters['email'] ?? ''),
      ),
      // 3 tab dưới đáy: Công thức, Cộng đồng, Hồ sơ. Mỗi tab giữ trạng thái riêng.
      // Màn con (chi tiết món, nấu, tạo bài, duyệt bài) mở trên navigator gốc nên che thanh tab.
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => MainShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => const RecipeListScreen(),
                routes: [
                  GoRoute(
                    path: 'lucky',
                    parentNavigatorKey: _rootKey,
                    builder: (_, _) => const LuckyMealScreen(),
                  ),
                  GoRoute(
                    path: 'recipes/:id',
                    parentNavigatorKey: _rootKey,
                    builder: (_, state) => RecipeDetailScreen(
                      recipeId: int.parse(state.pathParameters['id']!),
                    ),
                    routes: [
                      GoRoute(
                        path: 'cook',
                        parentNavigatorKey: _rootKey,
                        builder: (_, state) => CookingScreen(
                          recipeId: int.parse(state.pathParameters['id']!),
                          servings: int.tryParse(
                              state.uri.queryParameters['servings'] ?? ''),
                          voiceNext: state.uri.queryParameters['voice'] == 'next',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/community',
                builder: (_, _) => const CommunityFeedScreen(),
                routes: [
                  GoRoute(
                    path: 'new',
                    parentNavigatorKey: _rootKey,
                    builder: (_, _) => const CreatePostScreen(),
                  ),
                  GoRoute(
                    path: 'mine',
                    parentNavigatorKey: _rootKey,
                    builder: (_, _) => const MyPostsScreen(),
                  ),
                  GoRoute(
                    path: 'edit/:id',
                    parentNavigatorKey: _rootKey,
                    builder: (_, state) => CreatePostScreen(
                      editId: int.parse(state.pathParameters['id']!),
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
            ],
          ),
        ],
      ),
    ],
  );
}
