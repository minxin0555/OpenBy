import Darwin
import OpenBy

var cases: [MiniTest.Case] = []
cases += PathMatcherTests.cases
cases += RuleEngineTests.cases
cases += ConfigurationStoreTests.cases
cases += ConfigurationMigrationTests.cases
cases += AssociationServiceTests.cases
cases += ApplicationResolverTests.cases
cases += WorkspaceOpeningTests.cases

let allPassed = MiniTest.run(cases)
exit(allPassed ? 0 : 1)
