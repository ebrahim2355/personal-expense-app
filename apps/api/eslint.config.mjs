import eslint from '@eslint/js';
import globals from 'globals';
import tseslint from 'typescript-eslint';

export default tseslint.config(
  {
    ignores: [
      'coverage/**',
      'dist/**',
      'eslint.config.mjs',
      'src/generated/**',
    ],
  },
  eslint.configs.recommended,
  ...tseslint.configs.strictTypeChecked,
  ...tseslint.configs.stylisticTypeChecked,
  {
    languageOptions: {
      globals: globals.node,
      parserOptions: {
        projectService: true,
        tsconfigRootDir: import.meta.dirname,
      },
    },
    rules: {
      '@typescript-eslint/consistent-type-imports': [
        'error',
        { prefer: 'type-imports' },
      ],
      '@typescript-eslint/no-unused-vars': [
        'error',
        { argsIgnorePattern: '^_' },
      ],
    },
  },
  {
    files: [
      'src/application/sync-service.ts',
      'src/domain/validation.ts',
      'src/infrastructure/token-service.ts',
    ],
    rules: {
      // Zod 4 retains these stable APIs; migrating them is separate from this milestone.
      '@typescript-eslint/no-deprecated': 'off',
    },
  },
  {
    files: ['src/domain/validation.ts'],
    rules: {
      // Product validation explicitly counts Unicode code points, not graphemes.
      '@typescript-eslint/no-misused-spread': 'off',
    },
  },
  {
    files: [
      'src/application/auth-service.ts',
      'src/http/error-handler.ts',
      'test/integration/api.integration.test.ts',
    ],
    rules: {
      // These defensive runtime checks intentionally survive narrower TS types.
      '@typescript-eslint/no-unnecessary-condition': 'off',
    },
  },
);
