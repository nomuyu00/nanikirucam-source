/**
 * Firebase エミュレータ（Firestore / Storage）を使うテスト。
 * `npm run test:emulator`（firebase emulators:exec 経由）で実行する。
 */
module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  roots: ['<rootDir>/test/emulator'],
  testMatch: ['**/*.etest.ts'],
  testTimeout: 30000,
  transform: {
    '^.+\.ts$': ['ts-jest', { tsconfig: 'tsconfig.json' }],
  },
};
