import js from '@eslint/js';

export default [
  { ignores: ['dist/**', 'coverage/**', 'node_modules/**', '.env', '.env.*'] },
  js.configs.recommended,
  {
    files: ['**/*.js'],
    languageOptions: {
      ecmaVersion: 'latest',
      sourceType: 'module',
      globals: Object.fromEntries(
        [
          'AbortController',
          'AbortSignal',
          'DOMException',
          'URL',
          'URLSearchParams',
          'document',
          'window',
          'fetch',
          'setTimeout',
          'clearTimeout',
          'ResizeObserver',
          'Response',
        ].map((name) => [name, 'readonly']),
      ),
    },
    rules: {
      eqeqeq: ['error', 'always'],
      'no-var': 'error',
      'prefer-const': 'error',
      'no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
    },
  },
];
