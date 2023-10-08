open Ava
open RescriptCore

let validAsyncRefine = S.transform(_, _ => {
  asyncParser: value => () => value->Promise.resolve,
})
let invalidSyncRefine = S.refine(_, s => _ => s.fail("Sync user error"))
let unresolvedPromise = Promise.make((_, _) => ())
let makeInvalidPromise = (s: S.effectCtx<'a>) =>
  Promise.resolve()->Promise.then(() => s.fail("Async user error"))
let invalidAsyncRefine = S.transform(_, s => {
  asyncParser: _ => () => makeInvalidPromise(s),
})

asyncTest("Successfully parses without asyncRefine", t => {
  let struct = S.string

  (
    %raw(`"Hello world!"`)->S.parseAnyAsyncInStepsWith(struct)->Result.getExn
  )()->Promise.thenResolve(result => {
    t->Assert.deepEqual(result, Ok("Hello world!"), ())
  })
})

test("Fails to parse without asyncRefine", t => {
  let struct = S.string

  t->Assert.deepEqual(
    %raw(`123`)->S.parseAnyAsyncInStepsWith(struct),
    Error(
      U.error({
        code: InvalidType({expected: struct->S.toUnknown, received: %raw(`123`)}),
        operation: Parsing,
        path: S.Path.empty,
      }),
    ),
    (),
  )
})

asyncTest("Successfully parses with validAsyncRefine", t => {
  let struct = S.string->validAsyncRefine

  (
    %raw(`"Hello world!"`)->S.parseAnyAsyncInStepsWith(struct)->Result.getExn
  )()->Promise.thenResolve(result => {
    t->Assert.deepEqual(result, Ok("Hello world!"), ())
  })
})

asyncTest("Fails to parse with invalidAsyncRefine", t => {
  let struct = S.string->invalidAsyncRefine

  (
    %raw(`"Hello world!"`)->S.parseAnyAsyncInStepsWith(struct)->Result.getExn
  )()->Promise.thenResolve(result => {
    t->Assert.deepEqual(
      result,
      Error(
        U.error({
          code: OperationFailed("Async user error"),
          operation: Parsing,
          path: S.Path.empty,
        }),
      ),
      (),
    )
  })
})

module Object = {
  asyncTest("[Object] Successfully parses", t => {
    let struct = S.object(s =>
      {
        "k1": s.field("k1", S.int),
        "k2": s.field("k2", S.int->validAsyncRefine),
        "k3": s.field("k3", S.int),
      }
    )

    (
      {
        "k1": 1,
        "k2": 2,
        "k3": 3,
      }
      ->S.parseAnyAsyncInStepsWith(struct)
      ->Result.getExn
    )()->Promise.thenResolve(result => {
      t->Assert.deepEqual(
        result,
        Ok({
          "k1": 1,
          "k2": 2,
          "k3": 3,
        }),
        (),
      )
    })
  })

  asyncTest("[Object] Successfully parses async object in array", t => {
    let struct = S.array(
      S.object(s =>
        {
          "k1": s.field("k1", S.int),
          "k2": s.field("k2", S.int->validAsyncRefine),
          "k3": s.field("k3", S.int),
        }
      ),
    )

    (
      [
        {
          "k1": 1,
          "k2": 2,
          "k3": 3,
        },
        {
          "k1": 4,
          "k2": 5,
          "k3": 6,
        },
      ]
      ->S.parseAnyAsyncInStepsWith(struct)
      ->Result.getExn
    )()->Promise.thenResolve(result => {
      t->Assert.deepEqual(
        result,
        Ok([
          {
            "k1": 1,
            "k2": 2,
            "k3": 3,
          },
          {
            "k1": 4,
            "k2": 5,
            "k3": 6,
          },
        ]),
        (),
      )
    })
  })

  asyncTest("[Object] Keeps fields in the correct order", t => {
    let struct = S.object(s =>
      {
        "k1": s.field("k1", S.int),
        "k2": s.field("k2", S.int->validAsyncRefine),
        "k3": s.field("k3", S.int),
      }
    )

    (
      {
        "k1": 1,
        "k2": 2,
        "k3": 3,
      }
      ->S.parseAnyAsyncInStepsWith(struct)
      ->Result.getExn
    )()->Promise.thenResolve(result => {
      t->Assert.deepEqual(
        result->Result.map(U.magic)->Result.map(Dict.keysToArray),
        Ok(["k1", "k2", "k3"]),
        (),
      )
    })
  })

  asyncTest("[Object] Successfully parses with valid async discriminant", t => {
    let struct = S.object(s => {
      ignore(s.field("discriminant", S.literal(true)->validAsyncRefine))
      {
        "k1": s.field("k1", S.int),
        "k2": s.field("k2", S.int),
        "k3": s.field("k3", S.int),
      }
    })

    (
      {
        "discriminant": true,
        "k1": 1,
        "k2": 2,
        "k3": 3,
      }
      ->S.parseAnyAsyncInStepsWith(struct)
      ->Result.getExn
    )()->Promise.thenResolve(result => {
      t->Assert.deepEqual(
        result,
        Ok({
          "k1": 1,
          "k2": 2,
          "k3": 3,
        }),
        (),
      )
    })
  })

  asyncTest("[Object] Fails to parse with invalid async discriminant", t => {
    let struct = S.object(s => {
      ignore(s.field("discriminant", S.literal(true)->invalidAsyncRefine))
      {
        "k1": s.field("k1", S.int),
        "k2": s.field("k2", S.int),
        "k3": s.field("k3", S.int),
      }
    })

    (
      {
        "discriminant": true,
        "k1": 1,
        "k2": 2,
        "k3": 3,
      }
      ->S.parseAnyAsyncInStepsWith(struct)
      ->Result.getExn
    )()->Promise.thenResolve(result => {
      t->Assert.deepEqual(
        result,
        Error(
          U.error({
            code: OperationFailed("Async user error"),
            operation: Parsing,
            path: S.Path.fromArray(["discriminant"]),
          }),
        ),
        (),
      )
    })
  })

  test("[Object] Returns sync error when fails to parse sync part of async item", t => {
    let invalidStruct = S.int->validAsyncRefine
    let struct = S.object(s =>
      {
        "k1": s.field("k1", S.int),
        "k2": s.field("k2", invalidStruct),
        "k3": s.field("k3", S.int),
      }
    )

    t->Assert.deepEqual(
      {
        "k1": 1,
        "k2": true,
        "k3": 3,
      }->S.parseAnyAsyncInStepsWith(struct),
      Error(
        U.error({
          code: InvalidType({expected: invalidStruct->S.toUnknown, received: %raw(`true`)}),
          operation: Parsing,
          path: S.Path.fromArray(["k2"]),
        }),
      ),
      (),
    )
  })

  test("[Object] Parses sync items first, and then starts parsing async ones", t => {
    let struct = S.object(s =>
      {
        "k1": s.field("k1", S.int),
        "k2": s.field("k2", S.int->invalidAsyncRefine),
        "k3": s.field("k3", S.int->invalidSyncRefine),
      }
    )

    t->Assert.deepEqual(
      {
        "k1": 1,
        "k2": 2,
        "k3": 3,
      }->S.parseAnyAsyncInStepsWith(struct),
      Error(
        U.error({
          code: OperationFailed("Sync user error"),
          operation: Parsing,
          path: S.Path.fromArray(["k3"]),
        }),
      ),
      (),
    )
  })

  test("[Object] Parses async items in parallel", t => {
    let actionCounter = ref(0)

    let struct = S.object(s =>
      {
        "k1": s.field(
          "k1",
          S.int->S.transform(
            _ => {
              asyncParser: _ => () => {
                actionCounter.contents = actionCounter.contents + 1
                unresolvedPromise
              },
            },
          ),
        ),
        "k2": s.field(
          "k2",
          S.int->S.transform(
            _ => {
              asyncParser: _ => () => {
                actionCounter.contents = actionCounter.contents + 1
                unresolvedPromise
              },
            },
          ),
        ),
      }
    )

    {
      "k1": 1,
      "k2": 2,
    }
    ->S.parseAnyAsyncWith(struct)
    ->ignore

    t->Assert.deepEqual(actionCounter.contents, 2, ())
  })

  asyncTest("[Object] Doesn't wait for pending async items when fails to parse", t => {
    let struct = S.object(s =>
      {
        "k1": s.field(
          "k1",
          S.int->S.transform(
            _ => {
              asyncParser: _ => () => unresolvedPromise,
            },
          ),
        ),
        "k2": s.field("k2", S.int->invalidAsyncRefine),
      }
    )

    (
      {
        "k1": 1,
        "k2": 2,
      }
      ->S.parseAnyAsyncInStepsWith(struct)
      ->Result.getExn
    )()->Promise.thenResolve(result => {
      t->Assert.deepEqual(
        result,
        Error(
          U.error({
            code: OperationFailed("Async user error"),
            operation: Parsing,
            path: S.Path.fromArray(["k2"]),
          }),
        ),
        (),
      )
    })
  })
}

module Tuple = {
  asyncTest("[Tuple] Successfully parses", t => {
    let struct = S.tuple3(S.int, S.int->validAsyncRefine, S.int)

    (
      [1, 2, 3]->S.parseAnyAsyncInStepsWith(struct)->Result.getExn
    )()->Promise.thenResolve(result => {
      t->Assert.deepEqual(result, Ok(1, 2, 3), ())
    })
  })

  test("[Tuple] Returns sync error when fails to parse sync part of async item", t => {
    let invalidStruct = S.int->validAsyncRefine
    let struct = S.tuple3(S.int, invalidStruct, S.int)

    t->Assert.deepEqual(
      %raw(`[1, true, 3]`)->S.parseAnyAsyncInStepsWith(struct),
      Error(
        U.error({
          code: InvalidType({expected: invalidStruct->S.toUnknown, received: %raw(`true`)}),
          operation: Parsing,
          path: S.Path.fromArray(["1"]),
        }),
      ),
      (),
    )
  })

  test("[Tuple] Parses sync items first, and then starts parsing async ones", t => {
    let struct = S.tuple3(
      S.int,
      S.int->invalidSyncRefine->invalidAsyncRefine,
      S.int->invalidSyncRefine,
    )

    t->Assert.deepEqual(
      [1, 2, 3]->S.parseAnyAsyncInStepsWith(struct),
      Error(
        U.error({
          code: OperationFailed("Sync user error"),
          operation: Parsing,
          path: S.Path.fromArray(["1"]),
        }),
      ),
      (),
    )
  })

  test("[Tuple] Parses async items in parallel", t => {
    let actionCounter = ref(0)

    let struct = S.tuple2(
      S.int->S.transform(_ => {
        asyncParser: _ => () => {
          actionCounter.contents = actionCounter.contents + 1
          unresolvedPromise
        },
      }),
      S.int->S.transform(_ => {
        asyncParser: _ => () => {
          actionCounter.contents = actionCounter.contents + 1
          unresolvedPromise
        },
      }),
    )

    [1, 2]->S.parseAnyAsyncWith(struct)->ignore

    t->Assert.deepEqual(actionCounter.contents, 2, ())
  })

  asyncTest("[Tuple] Doesn't wait for pending async items when fails to parse", t => {
    let struct = S.tuple2(
      S.int->S.transform(_ => {asyncParser: _ => () => unresolvedPromise}),
      S.int->invalidAsyncRefine,
    )

    ([1, 2]->S.parseAnyAsyncInStepsWith(struct)->Result.getExn)()->Promise.thenResolve(result => {
      t->Assert.deepEqual(
        result,
        Error(
          U.error({
            code: OperationFailed("Async user error"),
            operation: Parsing,
            path: S.Path.fromArray(["1"]),
          }),
        ),
        (),
      )
    })
  })
}

module Union = {
  asyncTest("[Union] Successfully parses", t => {
    let struct = S.union([S.literal(1), S.literal(2)->validAsyncRefine, S.literal(3)])

    Promise.all([
      (1->S.parseAnyAsyncInStepsWith(struct)->Result.getExn)()->Promise.thenResolve(result => {
        t->Assert.deepEqual(result, Ok(1), ())
      }),
      (2->S.parseAnyAsyncInStepsWith(struct)->Result.getExn)()->Promise.thenResolve(result => {
        t->Assert.deepEqual(result, Ok(2), ())
      }),
      (3->S.parseAnyAsyncInStepsWith(struct)->Result.getExn)()->Promise.thenResolve(result => {
        t->Assert.deepEqual(result, Ok(3), ())
      }),
    ])->Promise.thenResolve(_ => ())
  })

  asyncTest("[Union] Doesn't return sync error when fails to parse sync part of async item", t => {
    let struct = S.union([S.literal(1), S.literal(2)->validAsyncRefine, S.literal(3)])
    let input = %raw("true")

    (input->S.parseAnyAsyncInStepsWith(struct)->Result.getExn)()->Promise.thenResolve(result => {
      t->Assert.deepEqual(
        result,
        Error(
          U.error({
            code: InvalidUnion([
              U.error({
                code: InvalidLiteral({expected: Number(1.), received: input}),
                path: S.Path.empty,
                operation: Parsing,
              }),
              U.error({
                code: InvalidLiteral({expected: Number(2.), received: input}),
                path: S.Path.empty,
                operation: Parsing,
              }),
              U.error({
                code: InvalidLiteral({expected: Number(3.), received: input}),
                path: S.Path.empty,
                operation: Parsing,
              }),
            ]),
            operation: Parsing,
            path: S.Path.empty,
          }),
        ),
        (),
      )
    })
  })

  test("[Union] Parses async items in parallel", t => {
    let actionCounter = ref(0)

    let struct = S.union([
      S.literal(2)->S.transform(_ => {
        asyncParser: _ => () => {
          actionCounter.contents = actionCounter.contents + 1
          unresolvedPromise
        },
      }),
      S.literal(2)->S.transform(_ => {
        asyncParser: _ => () => {
          actionCounter.contents = actionCounter.contents + 1
          unresolvedPromise
        },
      }),
    ])

    2->S.parseAnyAsyncWith(struct)->ignore

    t->Assert.deepEqual(actionCounter.contents, 2, ())
  })
}

module Array = {
  asyncTest("[Array] Successfully parses", t => {
    let struct = S.array(S.int->validAsyncRefine)

    (
      [1, 2, 3]->S.parseAnyAsyncInStepsWith(struct)->Result.getExn
    )()->Promise.thenResolve(result => {
      t->Assert.deepEqual(result, Ok([1, 2, 3]), ())
    })
  })

  test("[Array] Returns sync error when fails to parse sync part of async item", t => {
    let invalidStruct = S.int->validAsyncRefine
    let struct = S.array(invalidStruct)

    t->Assert.deepEqual(
      %raw(`[1, 2, true]`)->S.parseAnyAsyncInStepsWith(struct),
      Error(
        U.error({
          code: InvalidType({expected: invalidStruct->S.toUnknown, received: %raw(`true`)}),
          operation: Parsing,
          path: S.Path.fromArray(["2"]),
        }),
      ),
      (),
    )
  })

  test("[Array] Parses async items in parallel", t => {
    let actionCounter = ref(0)

    let struct = S.array(
      S.int->S.transform(_ => {
        asyncParser: _ => () => {
          actionCounter.contents = actionCounter.contents + 1
          unresolvedPromise
        },
      }),
    )

    [1, 2]->S.parseAnyAsyncWith(struct)->ignore

    t->Assert.deepEqual(actionCounter.contents, 2, ())
  })

  asyncTest("[Array] Doesn't wait for pending async items when fails to parse", t => {
    let actionCounter = ref(0)

    let struct = S.array(
      S.int->S.transform(s => {
        asyncParser: _ => () => {
          actionCounter.contents = actionCounter.contents + 1
          if actionCounter.contents <= 2 {
            unresolvedPromise
          } else {
            makeInvalidPromise(s)
          }
        },
      }),
    )

    (
      [1, 2, 3]->S.parseAnyAsyncInStepsWith(struct)->Result.getExn
    )()->Promise.thenResolve(result => {
      t->Assert.deepEqual(
        result,
        Error(
          U.error({
            code: OperationFailed("Async user error"),
            operation: Parsing,
            path: S.Path.fromArray(["2"]),
          }),
        ),
        (),
      )
    })
  })
}

module Dict = {
  asyncTest("[Dict] Successfully parses", t => {
    let struct = S.dict(S.int->validAsyncRefine)

    (
      {"k1": 1, "k2": 2, "k3": 3}->S.parseAnyAsyncInStepsWith(struct)->Result.getExn
    )()->Promise.thenResolve(result => {
      t->Assert.deepEqual(result, Ok(Dict.fromArray([("k1", 1), ("k2", 2), ("k3", 3)])), ())
    })
  })

  test("[Dict] Returns sync error when fails to parse sync part of async item", t => {
    let invalidStruct = S.int->validAsyncRefine
    let struct = S.dict(invalidStruct)

    t->Assert.deepEqual(
      {"k1": 1, "k2": 2, "k3": true}->S.parseAnyAsyncInStepsWith(struct),
      Error(
        U.error({
          code: InvalidType({expected: invalidStruct->S.toUnknown, received: %raw(`true`)}),
          operation: Parsing,
          path: S.Path.fromArray(["k3"]),
        }),
      ),
      (),
    )
  })

  test("[Dict] Parses async items in parallel", t => {
    let actionCounter = ref(0)

    let struct = S.dict(
      S.int->S.transform(_ => {
        asyncParser: _ => () => {
          actionCounter.contents = actionCounter.contents + 1
          unresolvedPromise
        },
      }),
    )

    {"k1": 1, "k2": 2}->S.parseAnyAsyncWith(struct)->ignore

    t->Assert.deepEqual(actionCounter.contents, 2, ())
  })

  asyncTest("[Dict] Doesn't wait for pending async items when fails to parse", t => {
    let actionCounter = ref(0)

    let struct = S.dict(
      S.int->S.transform(s => {
        asyncParser: _ => () => {
          actionCounter.contents = actionCounter.contents + 1
          if actionCounter.contents <= 2 {
            unresolvedPromise
          } else {
            makeInvalidPromise(s)
          }
        },
      }),
    )

    (
      {"k1": 1, "k2": 2, "k3": 3}->S.parseAnyAsyncInStepsWith(struct)->Result.getExn
    )()->Promise.thenResolve(result => {
      t->Assert.deepEqual(
        result,
        Error(
          U.error({
            code: OperationFailed("Async user error"),
            operation: Parsing,
            path: S.Path.fromArray(["k3"]),
          }),
        ),
        (),
      )
    })
  })
}

module Null = {
  asyncTest("[Null] Successfully parses", t => {
    let struct = S.null(S.int->validAsyncRefine)

    Promise.all([
      (1->S.parseAnyAsyncInStepsWith(struct)->Result.getExn)()->Promise.thenResolve(result => {
        t->Assert.deepEqual(result, Ok(Some(1)), ())
      }),
      (
        %raw(`null`)->S.parseAnyAsyncInStepsWith(struct)->Result.getExn
      )()->Promise.thenResolve(result => {
        t->Assert.deepEqual(result, Ok(None), ())
      }),
    ])->Promise.thenResolve(_ => ())
  })

  asyncTest("[Null] Fails to parse with invalid async refine", t => {
    let struct = S.null(S.int->invalidAsyncRefine)

    (1->S.parseAnyAsyncInStepsWith(struct)->Result.getExn)()->Promise.thenResolve(result => {
      t->Assert.deepEqual(
        result,
        Error(
          U.error({
            code: OperationFailed("Async user error"),
            operation: Parsing,
            path: S.Path.empty,
          }),
        ),
        (),
      )
    })
  })

  test("[Null] Returns sync error when fails to parse sync part of async item", t => {
    let struct = S.null(S.int->validAsyncRefine)

    t->Assert.deepEqual(
      true->S.parseAnyAsyncInStepsWith(struct),
      Error(
        U.error({
          code: InvalidType({expected: struct->S.toUnknown, received: %raw(`true`)}),
          operation: Parsing,
          path: S.Path.empty,
        }),
      ),
      (),
    )
  })
}

module Option = {
  asyncTest("[Option] Successfully parses", t => {
    let struct = S.option(S.int->validAsyncRefine)

    Promise.all([
      (1->S.parseAnyAsyncInStepsWith(struct)->Result.getExn)()->Promise.thenResolve(result => {
        t->Assert.deepEqual(result, Ok(Some(1)), ())
      }),
      (
        %raw(`undefined`)->S.parseAnyAsyncInStepsWith(struct)->Result.getExn
      )()->Promise.thenResolve(result => {
        t->Assert.deepEqual(result, Ok(None), ())
      }),
    ])->Promise.thenResolve(_ => ())
  })

  asyncTest("[Option] Fails to parse with invalid async refine", t => {
    let struct = S.option(S.int->invalidAsyncRefine)

    (1->S.parseAnyAsyncInStepsWith(struct)->Result.getExn)()->Promise.thenResolve(result => {
      t->Assert.deepEqual(
        result,
        Error(
          U.error({
            code: OperationFailed("Async user error"),
            operation: Parsing,
            path: S.Path.empty,
          }),
        ),
        (),
      )
    })
  })

  test("[Option] Returns sync error when fails to parse sync part of async item", t => {
    let struct = S.option(S.int->validAsyncRefine)

    t->Assert.deepEqual(
      true->S.parseAnyAsyncInStepsWith(struct),
      Error(
        U.error({
          code: InvalidType({expected: struct->S.toUnknown, received: %raw(`true`)}),
          operation: Parsing,
          path: S.Path.empty,
        }),
      ),
      (),
    )
  })
}

module Defaulted = {
  asyncTest("[Default] Successfully parses", t => {
    let struct = S.int->validAsyncRefine->validAsyncRefine->S.option->S.Option.getOrWith(() => 10)

    Promise.all([
      (1->S.parseAnyAsyncInStepsWith(struct)->Result.getExn)()->Promise.thenResolve(result => {
        t->Assert.deepEqual(result, Ok(1), ())
      }),
      (
        %raw(`undefined`)->S.parseAnyAsyncInStepsWith(struct)->Result.getExn
      )()->Promise.thenResolve(result => {
        t->Assert.deepEqual(result, Ok(10), ())
      }),
    ])->Promise.thenResolve(_ => ())
  })

  asyncTest("[Default] Fails to parse with invalid async refine", t => {
    let struct = S.int->invalidAsyncRefine->S.option->S.Option.getOrWith(() => 10)

    (1->S.parseAnyAsyncInStepsWith(struct)->Result.getExn)()->Promise.thenResolve(result => {
      t->Assert.deepEqual(
        result,
        Error(
          U.error({
            code: OperationFailed("Async user error"),
            operation: Parsing,
            path: S.Path.empty,
          }),
        ),
        (),
      )
      ()
    })
  })

  test("[Default] Returns sync error when fails to parse sync part of async item", t => {
    let struct = S.int->validAsyncRefine->S.option->S.Option.getOrWith(() => 10)

    t->Assert.deepEqual(
      true->S.parseAnyAsyncInStepsWith(struct),
      Error(
        U.error({
          code: InvalidType({expected: struct->S.toUnknown, received: %raw(`true`)}),
          operation: Parsing,
          path: S.Path.empty,
        }),
      ),
      (),
    )
  })
}

module Json = {
  asyncTest("[JsonString] Successfully parses", t => {
    let struct = S.jsonString(S.int->validAsyncRefine)

    ("1"->S.parseAnyAsyncInStepsWith(struct)->Result.getExn)()->Promise.thenResolve(result => {
      t->Assert.deepEqual(result, Ok(1), ())
    })
  })

  asyncTest("[JsonString] Fails to parse with invalid async refine", t => {
    let struct = S.jsonString(S.int->invalidAsyncRefine)

    ("1"->S.parseAnyAsyncInStepsWith(struct)->Result.getExn)()->Promise.thenResolve(result => {
      t->Assert.deepEqual(
        result,
        Error(
          U.error({
            code: OperationFailed("Async user error"),
            operation: Parsing,
            path: S.Path.empty,
          }),
        ),
        (),
      )
      ()
    })
  })

  test("[JsonString] Returns sync error when fails to parse sync part of async item", t => {
    let invalidStruct = S.int->validAsyncRefine
    let struct = S.jsonString(invalidStruct)

    t->Assert.deepEqual(
      "true"->S.parseAnyAsyncInStepsWith(struct),
      Error(
        U.error({
          code: InvalidType({expected: invalidStruct->S.toUnknown, received: %raw(`true`)}),
          operation: Parsing,
          path: S.Path.empty,
        }),
      ),
      (),
    )
  })
}