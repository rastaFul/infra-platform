/**
 * dependency-cruiser ruleset — enforces, as executable rules, the Clean
 * Architecture layering described in steering/architecture.md and the
 * Handler -> Service -> Repository pattern described in
 * steering/service-layers.md. Each `forbidden` rule below quotes the prose
 * line it translates.
 *
 * Assumed source layout (steering/architecture.md):
 *   src/domain/          entities, value objects, pure business rules
 *   src/application/     use cases, ports (interfaces), DTOs
 *   src/infrastructure/  adapters: db, http clients, queues, cache, repositories
 *   src/interface/       controllers/handlers/consumers/CLI + composition root
 *     src/interface/handlers/    Handler layer (steering/service-layers.md)
 *     src/interface/bootstrap/   DI composition root — architecture.md:
 *                                 "interface/ is the entry point. Composes
 *                                 everything via DI." This is the one place
 *                                 allowed to wire concrete infrastructure.
 *
 * If a target project uses different folder names, edit the `path` regexes
 * below — this file is a template copied by install.sh, not a fixed
 * contract, and is expected to be adjusted per project.
 */
module.exports = {
  forbidden: [
    {
      name: 'domain-zero-external-deps',
      comment:
        'architecture.md: "domain/ has ZERO external dependencies. Pure logic only." ' +
        'domain must not import any node_modules package.',
      severity: 'error',
      from: { path: '^src/domain' },
      to: { path: 'node_modules' },
    },
    {
      name: 'domain-no-upward-imports',
      comment:
        'architecture.md: "Dependency flow: interface -> application -> domain." ' +
        'domain must not import application, infrastructure or interface.',
      severity: 'error',
      from: { path: '^src/domain' },
      to: { path: '^src/(application|infrastructure|interface)' },
    },
    {
      name: 'application-never-imports-infrastructure',
      comment:
        'architecture.md: "application/ defines ports (interfaces). Never imports infrastructure."',
      severity: 'error',
      from: { path: '^src/application' },
      to: { path: '^src/infrastructure' },
    },
    {
      name: 'application-never-imports-interface',
      comment:
        'architecture.md: dependency flow is interface -> application -> domain; ' +
        'application must not depend back on the interface layer (controllers/handlers).',
      severity: 'error',
      from: { path: '^src/application' },
      to: { path: '^src/interface' },
    },
    {
      name: 'infrastructure-never-imports-interface',
      comment:
        'architecture.md: "infrastructure/ implements ports. Contains all external ' +
        'integrations." Infrastructure is composed BY the interface layer, it must ' +
        'not depend back on it.',
      severity: 'error',
      from: { path: '^src/infrastructure' },
      to: { path: '^src/interface' },
    },
    {
      name: 'handler-never-accesses-repository-directly',
      comment:
        'service-layers.md: "Handler NEVER contains business logic" and ' +
        '"No cross-layer logic (handler calling repository directly)". Handlers ' +
        '(src/interface/handlers) must go through a Service (src/application), not ' +
        'straight to infrastructure. src/interface/bootstrap is exempt — it is the ' +
        'DI composition root and must wire concrete repositories per architecture.md.',
      severity: 'error',
      from: { path: '^src/interface/handlers' },
      to: { path: '^src/infrastructure' },
    },
    {
      name: 'no-circular',
      comment:
        'Circular dependencies make the layering rules above meaningless in practice ' +
        '(every module can reach every other module transitively). Not an explicit ' +
        'steering-doc rule, kept as a low-severity structural safety net.',
      severity: 'warn',
      from: {},
      to: { circular: true },
    },
  ],
  options: {
    doNotFollow: {
      path: 'node_modules',
    },
    includeOnly: '^src',
    tsPreCompilationDeps: true,
    tsConfig: {
      fileName: 'tsconfig.json',
    },
  },
};
