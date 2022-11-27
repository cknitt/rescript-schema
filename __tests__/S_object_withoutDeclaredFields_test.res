open Ava

test("Successfully parses empty object", t => {
  let struct = S.object(_ => ())

  t->Assert.deepEqual(%raw(`{}`)->S.parseWith(struct), Ok(), ())
})

test("Successfully parses object with excess keys", t => {
  let struct = S.object(_ => ())

  t->Assert.deepEqual(%raw(`{field:"bar"}`)->S.parseWith(struct), Ok(), ())
})

test("Successfully parses empty object when UnknownKeys are strict", t => {
  let struct = S.object(_ => ())->S.Object.strict

  t->Assert.deepEqual(%raw(`{}`)->S.parseWith(struct), Ok(), ())
})

test("Fails to parse object with excess keys when UnknownKeys are strict", t => {
  let struct = S.object(_ => ())->S.Object.strict

  t->Assert.deepEqual(
    %raw(`{field:"bar"}`)->S.parseWith(struct),
    Error({
      code: ExcessField("field"),
      operation: Parsing,
      path: [],
    }),
    (),
  )
})

test("Successfully parses object with excess keys and returns transformed value", t => {
  let transformedValue = {"bas": true}
  let struct = S.object(_ => transformedValue)

  t->Assert.deepEqual(%raw(`{field:"bar"}`)->S.parseWith(struct), Ok(transformedValue), ())
})

test("Successfully serializes transformed value to empty object", t => {
  let transformedValue = {"bas": true}
  let struct = S.object(_ => transformedValue)

  t->Assert.deepEqual(transformedValue->S.serializeWith(struct), Ok(%raw("{}")), ())
})

test("Fails to parse array data", t => {
  let struct = S.object(_ => ())

  t->Assert.deepEqual(
    %raw(`[]`)->S.parseWith(struct),
    Error({
      code: UnexpectedType({expected: "Object", received: "Array"}),
      operation: Parsing,
      path: [],
    }),
    (),
  )
})