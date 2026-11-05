import js from "@eslint/js";
import tseslint from "typescript-eslint";
import reactHooks from "eslint-plugin-react-hooks";
import reactRefresh from "eslint-plugin-react-refresh";
import globals from "globals";

export default tseslint.config(
  { ignores: ["dist", "node_modules", "src-tauri/target"] },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    files: ["src/**/*.{ts,tsx}"],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: "module",
      globals: { ...globals.browser, ...globals.es2022 },
    },
    plugins: {
      "react-hooks": reactHooks,
      "react-refresh": reactRefresh,
    },
    rules: {
      // Rules-of-hooks is a real correctness guard; keep it an error.
      "react-hooks/rules-of-hooks": "error",
      // The codebase has intentional dep omissions (with eslint-disable lines);
      // surface new ones as warnings, not blocking errors.
      "react-hooks/exhaustive-deps": "warn",
      "react-refresh/only-export-components": ["warn", { allowConstantExport: true }],
      // Pragmatic defaults for a fast-moving app: don't fail the build on these.
      "@typescript-eslint/no-unused-vars": ["warn", { argsIgnorePattern: "^_", varsIgnorePattern: "^_" }],
      "@typescript-eslint/no-explicit-any": "off",
      // Empty catch blocks are an intentional "best effort" pattern here
      // (e.g. URL.revokeObjectURL, localStorage quota); allow them.
      "no-empty": ["error", { allowEmptyCatch: true }],
      // One pre-existing let-that-could-be-const; surface as a warning rather
      // than failing lint on day one.
      "prefer-const": "warn",
    },
  },
);
