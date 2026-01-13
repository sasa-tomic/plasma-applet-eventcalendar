#!/usr/bin/env node
/**
 * Simple test runner for QML JavaScript tests
 * Run with: node run_tests.js
 */

// Load the test file
const fs = require('fs');
const path = require('path');

// Read the test file and extract the functions
const testFilePath = path.join(__dirname, '../ui/code/NotificationCacheTests.js');
const testCode = fs.readFileSync(testFilePath, 'utf8');

// Remove .pragma library directive (not valid in Node.js)
const cleanCode = testCode.replace('.pragma library', '');

// Evaluate the test code
eval(cleanCode);

// Run all tests
const results = runAllTests();

// Print results
console.log('\n=== Notification Cache Tests ===\n');

results.results.forEach(result => {
	const status = result.passed ? '✓' : '✗';
	console.log(`${status} ${result.name}`);
	// Show message for all tests to clarify what's being tested
	console.log(`  → ${result.message}`);
});

console.log(`\n--- Summary ---`);
console.log(`Passed: ${results.passed}/${results.total}`);
console.log(`Failed: ${results.failed}/${results.total}`);

// Exit with error code if any tests failed
process.exit(results.failed > 0 ? 1 : 0);
