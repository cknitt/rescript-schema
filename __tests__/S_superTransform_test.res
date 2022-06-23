open Ava

let trimmedInSafeMode = S.superTransform(
  _,
  ~parser=(. ~value, ~struct as _, ~mode) =>
    switch mode {
    | Safe => value->Js.String2.trim
    | Unsafe => value
    }->Ok,
  ~serializer=(. ~transformed, ~struct as _, ~mode) =>
    switch mode {
    | Safe => transformed->Js.String2.trim
    | Unsafe => transformed
    }->Ok,
  (),
)

test("Successfully parses in Safe mode", t => {
  let struct = S.string()->trimmedInSafeMode

  t->Assert.deepEqual("  Hello world!"->S.parseWith(struct), Ok("Hello world!"), ())
})

test("Successfully parses in Unsafe mode with different logic", t => {
  let any = "  Hello world!"

  let struct = S.string()->trimmedInSafeMode

  t->Assert.deepEqual(any->S.parseWith(~mode=Unsafe, struct), Ok(any), ())
})

test("Throws for factory without either a parser, or a serializer", t => {
  t->Assert.throws(() => {
    S.string()->S.superTransform()->ignore
  }, ~expectations=ThrowsException.make(
    ~name="RescriptStructError",
    ~message="For a struct factory Transform either a parser, or a serializer is required",
    (),
  ), ())
})

test("Fails to parse when user returns error in parser", t => {
  let any = %raw(`"Hello world!"`)

  let struct =
    S.string()->S.superTransform(
      ~parser=(. ~value as _, ~struct as _, ~mode as _) => Error(S.Error.make("User error")),
      (),
    )

  t->Assert.deepEqual(
    any->S.parseWith(struct),
    Error({
      code: OperationFailed("User error"),
      operation: Parsing,
      path: [],
    }),
    (),
  )
})

test("Successfully serializes in Safe mode", t => {
  let struct = S.string()->trimmedInSafeMode

  t->Assert.deepEqual("  Hello world!"->S.serializeWith(struct), Ok(%raw(`"Hello world!"`)), ())
})

test("Successfully serializes in Unsafe mode with different logic", t => {
  let struct = S.string()->trimmedInSafeMode

  t->Assert.deepEqual(
    "  Hello world!"->S.serializeWith(~mode=Unsafe, struct),
    Ok(%raw(`"  Hello world!"`)),
    (),
  )
})

test("Fails to serialize when user returns error in serializer", t => {
  let value = "Hello world!"

  let struct =
    S.string()->S.superTransform(
      ~serializer=(. ~transformed as _, ~struct as _, ~mode as _) => Error(
        S.Error.make("User error"),
      ),
      (),
    )

  t->Assert.deepEqual(
    value->S.serializeWith(struct),
    Error({
      code: OperationFailed("User error"),
      operation: Serializing,
      path: [],
    }),
    (),
  )
})

test("Transform operations applyed in the right order when parsing", t => {
  let any = %raw(`123`)

  let struct =
    S.int()
    ->S.superTransform(
      ~parser=(. ~value as _, ~struct as _, ~mode as _) => Error(S.Error.make("First transform")),
      (),
    )
    ->S.superTransform(
      ~parser=(. ~value as _, ~struct as _, ~mode as _) => Error(S.Error.make("Second transform")),
      (),
    )

  t->Assert.deepEqual(
    any->S.parseWith(struct),
    Error({
      code: OperationFailed("First transform"),
      operation: Parsing,
      path: [],
    }),
    (),
  )
})

test("Transform operations applyed in the right order when serializing", t => {
  let any = %raw(`123`)

  let struct =
    S.int()
    ->S.superTransform(
      ~serializer=(. ~transformed as _, ~struct as _, ~mode as _) => Error(
        S.Error.make("Second transform"),
      ),
      (),
    )
    ->S.superTransform(
      ~serializer=(. ~transformed as _, ~struct as _, ~mode as _) => Error(
        S.Error.make("First transform"),
      ),
      (),
    )

  t->Assert.deepEqual(
    any->S.serializeWith(struct),
    Error({
      code: OperationFailed("First transform"),
      operation: Serializing,
      path: [],
    }),
    (),
  )
})